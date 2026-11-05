"""Exercise the assembled catalog API and CLI without CUDA or isotope .bin files."""
import csv
import ctypes as C
import hashlib
import io
import math
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

BINARY = Path(sys.argv.pop(1)).resolve()
LIBRARY = Path(sys.argv.pop(1)).resolve()
ROOT = Path(__file__).resolve().parents[1]


class Record(C.Structure):
    _fields_ = [('z', C.c_uint64), ('n', C.c_uint64), ('a', C.c_uint64),
                ('symbol', C.c_char * 8), ('half_life_seconds', C.c_double),
                ('decay_constant', C.c_double), ('sort_key', C.c_double),
                ('reserved', C.c_uint64)]


class Catalog(C.Structure):
    _fields_ = [('data', C.POINTER(Record)), ('count', C.c_size_t), ('bytes', C.c_size_t)]


LIB = C.CDLL(str(LIBRARY))
LIB.isotope_catalog_load.argtypes = [C.c_char_p, C.POINTER(Catalog)]
LIB.isotope_catalog_load.restype = C.c_int
LIB.isotope_catalog_free.argtypes = [C.POINTER(Catalog)]
LIB.isotope_catalog_free.restype = None
LIB.isotope_catalog_error.argtypes = [C.c_int]
LIB.isotope_catalog_error.restype = C.c_char_p


def isotope(z=1, n=2, symbol='H', k=.25, status='measured'):
    return [z, n, z+n, symbol, math.log(2)/k, k, status]


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='nuclideid-catalog-test-')
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        self.db = self.directory / 'isotopes.sqlite3'

    def create_db(self, rows):
        with sqlite3.connect(self.db) as con:
            con.execute('CREATE TABLE nuclides(z,n,a,symbol,half_life_seconds,decay_constant,status)')
            con.executemany('INSERT INTO nuclides VALUES(?,?,?,?,?,?,?)', rows)

    def load(self, expected=0):
        catalog = Catalog()
        code = LIB.isotope_catalog_load(str(self.db).encode(), C.byref(catalog))
        self.assertEqual(code, expected, LIB.isotope_catalog_error(code))
        self.addCleanup(LIB.isotope_catalog_free, C.byref(catalog))
        if expected:
            self.assertFalse(catalog.data)
            self.assertEqual((catalog.count, catalog.bytes), (0, 0))
        return catalog

    def run_cli(self, *args):
        return subprocess.run([str(BINARY), *args], cwd=self.directory,
                              capture_output=True, text=True, timeout=15)

    def test_layout_and_zeroed_symbols(self):
        self.assertEqual(C.sizeof(Record), 64)
        self.assertEqual(C.sizeof(Catalog), 24)
        self.assertEqual(Record.decay_constant.offset, 40)
        self.create_db([isotope(z=2, n=2, symbol='He')])
        catalog = self.load()
        self.assertEqual((catalog.count, catalog.bytes), (1, 64))
        r = catalog.data[0]
        self.assertEqual((r.z, r.n, r.a, r.symbol), (2, 2, 4, b'He'))
        self.assertEqual(r.sort_key, r.decay_constant)
        self.assertEqual(r.reserved, 0)
        self.assertEqual(C.string_at(C.addressof(r)+24, 8), b'He' + b'\0'*6)

    def test_filters_sorting_large_constants_and_ties(self):
        rows = [isotope(n=3, k=8e21), isotope(n=5, k=.1), isotope(n=2, k=.1),
                isotope(z=2, n=1, symbol='He', k=.1), isotope(n=8, status='qualified'),
                [1, 0, 1, 'H', None, 0, 'stable'], [42, 40, 82, 'Mo', None, None, 'unknown']]
        self.create_db(rows)
        catalog = self.load()
        actual = [(catalog.data[i].decay_constant, catalog.data[i].z, catalog.data[i].n)
                  for i in range(catalog.count)]
        self.assertEqual(actual, sorted((r[5], r[0], r[1]) for r in rows if r[6]=='measured'))
        self.assertEqual(catalog.count, 4)
        self.assertEqual(actual[-1][0], 8e21)

    def test_dynamic_counts_without_power_of_two_padding(self):
        for count in [1, 2, 3, 63, 64, 65, 127, 128, 129, 255, 256, 257, 999]:
            with self.subTest(count=count):
                if self.db.exists(): self.db.unlink()
                self.create_db([isotope(n=i, k=(count-i)/100) for i in range(count)])
                catalog = self.load()
                self.assertEqual((catalog.count, catalog.bytes), (count, count*64))
                self.assertEqual([catalog.data[i].n for i in range(count)], list(reversed(range(count))))

    def test_read_only_source_no_bin_files_and_repeat(self):
        self.create_db([isotope()])
        before = self.db.read_bytes()
        self.db.chmod(0o444)
        for _ in range(3):
            self.load()
            run = self.run_cli()
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertIn('1 measured isotopes (64 bytes)', run.stdout)
        self.assertEqual(self.db.read_bytes(), before)
        self.assertEqual(sorted(p.name for p in self.directory.iterdir()), ['isotopes.sqlite3'])

    def test_list_matches_actual_memory(self):
        self.create_db([isotope(n=4, k=2), isotope(n=2, k=.1)])
        run = self.run_cli('--list')
        self.assertEqual(run.returncode, 0, run.stderr)
        rows = list(csv.DictReader(io.StringIO(run.stdout), delimiter='\t'))
        self.assertEqual([int(r['n']) for r in rows], [2, 4])
        self.assertEqual([float(r['decay_constant']) for r in rows], [.1, 2])

    def test_no_candidates(self):
        self.create_db([isotope(status='qualified'), [1,0,1,'H',None,0,'stable']])
        self.load(expected=4)
        run = self.run_cli()
        self.assertEqual(run.returncode, 1)
        self.assertIn('no unqualified measured', run.stderr)

    def test_missing_file_never_created(self):
        self.load(expected=2)
        self.assertFalse(self.db.exists())
        self.assertEqual(self.run_cli().returncode, 1)
        self.assertFalse(self.db.exists())

    def test_wrong_schema_and_corrupt_file(self):
        with sqlite3.connect(self.db): pass
        self.load(expected=2)
        self.db.write_bytes(b'not a database')
        self.load(expected=2)

    def test_invalid_numeric_values_and_types(self):
        for index, value in [(4, None), (5, None), (4, 0), (5, 0), (4, -2), (5, -2),
                             (4, float('inf')), (5, float('inf')), (4, float('nan')),
                             (4, '2'), (5, '0.25'), (5, 'garbage'), (5, .5)]:
            with self.subTest(index=index, value=value):
                if self.db.exists(): self.db.unlink()
                r = isotope(); r[index] = value
                self.create_db([r])
                self.load(expected=3)

    def test_bad_identities_and_symbols(self):
        for index, value in [(0,-1), (0,119), (0,'1'), (0,1.5), (1,-1),
                             (1,1001), (2,99), (3,'He'), (3,'H\0junk'),
                             (3,''), (3,None), (3,b'H')]:
            with self.subTest(index=index, value=value):
                if self.db.exists(): self.db.unlink()
                r=isotope(); r[index]=value
                self.create_db([r])
                self.load(expected=3)

    def test_free_lifetime_and_independent_catalogs(self):
        self.create_db([isotope()])
        first, second = self.load(), self.load()
        self.assertNotEqual(C.addressof(first.data.contents), C.addressof(second.data.contents))
        LIB.isotope_catalog_free(C.byref(first))
        self.assertFalse(first.data)
        self.assertEqual((first.count, first.bytes), (0, 0))
        LIB.isotope_catalog_free(C.byref(first))
        LIB.isotope_catalog_free(None)
        self.assertEqual(second.data[0].symbol, b'H')
        self.assertEqual(LIB.isotope_catalog_load(str(self.db).encode(), C.byref(first)), 0)

    def test_invalid_api_arguments_preserve_live_catalog(self):
        self.create_db([isotope()])
        catalog=self.load()
        before=C.string_at(C.byref(catalog), C.sizeof(catalog))
        self.assertEqual(LIB.isotope_catalog_load(str(self.db).encode(), C.byref(catalog)), 1)
        self.assertEqual(C.string_at(C.byref(catalog), C.sizeof(catalog)), before)
        empty=Catalog()
        self.assertEqual(LIB.isotope_catalog_load(None, C.byref(empty)), 1)
        self.assertEqual(LIB.isotope_catalog_load(b'', C.byref(empty)), 1)
        self.assertEqual(LIB.isotope_catalog_load(str(self.db).encode(), None), 1)

    def test_cli_options(self):
        self.assertEqual(self.run_cli('--help').returncode, 0)
        for args in [('-o','file.bin'), ('--bad',), ('a','b'), ('',), ('--list','--list'), ('--help','a')]:
            self.assertEqual(self.run_cli(*args).returncode, 1)
        self.assertFalse(list(self.directory.iterdir()))

    def test_cleanup_after_many_partial_failures(self):
        self.create_db([isotope(n=1,k=.1), isotope(n=2,k=.2)])
        with sqlite3.connect(self.db) as con:
            con.execute('UPDATE nuclides SET half_life_seconds=-1 WHERE n=2')
        fd_dir=Path('/proc/self/fd')
        before=len(list(fd_dir.iterdir()))
        for _ in range(40): self.load(expected=3)
        self.assertLessEqual(len(list(fd_dir.iterdir())), before)

    @unittest.skipUnless((ROOT/'isotopes.sqlite3').exists(), 'real SQLite catalog not available')
    def test_every_real_candidate(self):
        path=ROOT/'isotopes.sqlite3'
        before=hashlib.sha256(path.read_bytes()).digest()
        with sqlite3.connect(f'file:{path}?mode=ro', uri=True) as con:
            expected=con.execute("SELECT z,n,a,symbol,half_life_seconds,decay_constant FROM nuclides WHERE status='measured' ORDER BY decay_constant,z,n").fetchall()
        catalog=Catalog()
        self.assertEqual(LIB.isotope_catalog_load(str(path).encode(), C.byref(catalog)), 0)
        self.addCleanup(LIB.isotope_catalog_free, C.byref(catalog))
        self.assertEqual(catalog.count,len(expected))
        self.assertEqual(catalog.bytes,len(expected)*64)
        for i, row in enumerate(expected):
            r=catalog.data[i]
            self.assertEqual((r.z,r.n,r.a,r.symbol.decode(),r.half_life_seconds,r.decay_constant),row)
            self.assertEqual(r.sort_key,r.decay_constant)
            self.assertEqual(r.reserved,0)
        self.assertEqual(hashlib.sha256(path.read_bytes()).digest(),before)


if __name__ == '__main__': unittest.main()
