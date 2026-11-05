"""Integration tests for the assembled SQLite importer, using isolated files."""
import csv
import io
import math
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

BINARY = Path(sys.argv.pop(1)).resolve()
ROOT = Path(__file__).resolve().parents[1]
HEADER = (
    'z,n,symbol,radius,unc_r,abundance,unc_a,energy_shift,energy,unc_e,'
    'ripl_shift,jp,half_life,operator_hl,unc_hl,unit_hl,half_life_sec,'
    'unc_hls,decay_1,decay_1_%,unc_1,decay_2,decay_2_%,unc_2,decay_3,'
    'decay_3_%,unc_3,isospin,magnetic_dipole,unc_md,electric_quadrupole,'
    'unc_eq,qbm,unc_qb,qbm_n,unc_qbmn,qa,unc_qa,qec,unc_qec,sn,unc_sn,'
    'sp,unc_sp,binding,unc_ba,atomic_mass,unc_am,massexcess,unc_me,'
    'me_systematics,discovery,ENSDFpublicationcut-off,ENSDFauthors,Extraction_date'
).split(',')


def row(**changes):
    values = dict(z='1', n='2', symbol='H', half_life='2',
                  unit_hl='s', half_life_sec='2')
    values.update(changes)
    return [values.get(key, '') for key in HEADER]


def document(*rows, ending='\n'):
    output = io.StringIO(newline='')
    csv.writer(output, lineterminator=ending).writerows([HEADER, *rows])
    return output.getvalue()


class ImporterTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='nuclideid-sqlite-test-')
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        self.source = self.directory / 'isotopes.csv'
        self.db = self.directory / 'isotopes.sqlite3'

    def run_import(self, text, success=True, default_args=False):
        self.source.write_bytes(text.encode())
        args = [] if default_args else [str(self.source), str(self.db)]
        run = subprocess.run([str(BINARY), *args], cwd=self.directory,
                             capture_output=True, text=True, timeout=15)
        self.assertEqual(run.returncode, 0 if success else 1,
                         run.stdout + run.stderr)
        return run

    def records(self):
        with sqlite3.connect(self.db) as con:
            con.row_factory = sqlite3.Row
            return [dict(r) for r in con.execute('SELECT * FROM nuclides ORDER BY z,n')]

    def assert_rejected_preserving_database(self, text):
        self.run_import(document(row()))
        before = self.db.read_bytes()
        run = self.run_import(text, success=False)
        self.assertIn('line', run.stderr)
        self.assertEqual(self.records()[0]['half_life_seconds'], 2.0)
        self.assertEqual(self.db.read_bytes(), before)

    def test_measured_defaults_and_raw_source(self):
        text = document(row(ENSDFauthors='A, B "quoted"', unc_hl='+94-6'))
        self.run_import(text, default_args=True)
        record, = self.records()
        self.assertEqual((record['z'], record['n'], record['a']), (1, 2, 3))
        self.assertEqual(record['status'], 'measured')
        self.assertAlmostEqual(record['decay_constant'], math.log(2) / 2)
        self.assertEqual(record['uncertainty_raw'], '+94-6')
        self.assertEqual(next(csv.reader([record['source_csv']]))[53], 'A, B "quoted"')

    def test_statuses_and_no_binding_leak(self):
        self.run_import(document(
            row(),
            row(n='0', half_life='STABLE', unit_hl='', half_life_sec=''),
            row(z='42', n='40', symbol='Mo', half_life='?', unit_hl='', half_life_sec=''),
            row(z='2', n='8', symbol='He', operator_hl='LT'),
            row(z='3', n='8', symbol='Li', half_life='', unit_hl='', half_life_sec=''),
        ))
        records = {(r['z'], r['n']): r for r in self.records()}
        stable = records[1, 0]
        self.assertEqual(stable['status'], 'stable')
        self.assertIsNone(stable['half_life_seconds'])
        self.assertEqual(stable['decay_constant'], 0)
        for key in [(42, 40), (3, 8)]:
            self.assertEqual(records[key]['status'], 'unknown')
            self.assertIsNone(records[key]['half_life_seconds'])
            self.assertIsNone(records[key]['decay_constant'])
        self.assertEqual(records[2, 8]['status'], 'qualified')
        self.assertEqual(records[2, 8]['qualifier'], 'LT')

    def test_crlf_blank_records_and_final_empty_field_without_newline(self):
        text = document(row(), ending='\r\n').rstrip('\r\n')
        self.run_import(text)
        self.assertEqual(len(self.records()), 1)
        self.run_import(document(row()) + '\n\n')
        self.assertEqual(len(self.records()), 1)

    def test_scientific_notation_and_decimal_fraction(self):
        self.run_import(document(row(half_life='0.58', unit_hl='ms', half_life_sec='5.8e-4', radius='.00')))
        self.assertEqual(self.records()[0]['half_life_seconds'], .00058)

    def test_bad_numbers_rollback(self):
        for value in ['garbage', '0', '-2', 'NaN', 'inf', '2garbage', '1e309',
                      '1e-999', '0x1p0', ' 2', '2 ', '.', '1e', '1e-']:
            with self.subTest(value=value):
                self.assert_rejected_preserving_database(document(row(half_life_sec=value)))

    def test_invalid_other_numeric_fields(self):
        for key, value in [('radius', 'garbage'), ('unc_r', '-1'),
                           ('abundance', '101'), ('decay_1_%', '-1'),
                           ('unc_hl', '+2-'), ('unc_hl', 'abc')]:
            with self.subTest(key=key, value=value):
                self.assert_rejected_preserving_database(document(row(**{key: value})))

    def test_invalid_identity(self):
        for changes in [dict(z='-1'), dict(z='119'), dict(z='a'), dict(n='1.0'),
                        dict(n='1001'), dict(z='0', n='0', symbol='n'),
                        dict(symbol='He'), dict(z='99999999999999999999')]:
            with self.subTest(changes=changes):
                self.assert_rejected_preserving_database(document(row(**changes)))

    def test_invalid_half_life_combinations(self):
        for changes in [dict(half_life='STABLE'), dict(half_life='?'),
                        dict(half_life=''), dict(half_life_sec=''),
                        dict(half_life='-2'), dict(unit_hl='fortnight'),
                        dict(operator_hl='BAD')]:
            with self.subTest(changes=changes):
                self.assert_rejected_preserving_database(document(row(**changes)))

    def test_wrong_column_counts_and_quotes(self):
        for bad in ['1,2,H', ','.join(row() + ['extra']),
                    ','.join(row()) + ',extra', '"unterminated',
                    '1,2,"H"junk,' + ','.join(row()[3:]),
                    '1,2,H"bad,' + ','.join(row()[3:])]:
            with self.subTest(bad=bad):
                self.assert_rejected_preserving_database(','.join(HEADER) + '\n' + bad + '\n')

    def test_duplicate_and_failure_after_valid_row_roll_back(self):
        for rows in [(row(), row()), (row(n='3'), row(n='4', half_life_sec='bad'))]:
            self.assert_rejected_preserving_database(document(*rows))

    def test_empty_bad_header_and_nul_rejected(self):
        for text in ['', ','.join(HEADER) + '\n', 'wrong\n1,2,H\n',
                     document(row()).replace('H,', 'H\0,')]:
            with self.subTest(text=text[:20]):
                self.assert_rejected_preserving_database(text)

    def test_database_constraints(self):
        self.run_import(document(row()))
        with sqlite3.connect(self.db) as con:
            self.assertEqual(con.execute('PRAGMA integrity_check').fetchone()[0], 'ok')
            for sql in ["UPDATE nuclides SET half_life_seconds=-1",
                        "UPDATE nuclides SET z='bad'", "UPDATE nuclides SET a=999",
                        "UPDATE nuclides SET status='unknown'",
                        "UPDATE nuclides SET decay_constant=NULL"]:
                with self.subTest(sql=sql), self.assertRaises(sqlite3.IntegrityError):
                    con.execute(sql)

    def test_rerun_replaces_records(self):
        self.run_import(document(row(), row(n='3')))
        self.run_import(document(row(n='4')))
        self.assertEqual([r['n'] for r in self.records()], [4])

    def test_help_and_invalid_arguments(self):
        run = subprocess.run([str(BINARY), '--help'], capture_output=True, text=True)
        self.assertEqual(run.returncode, 0)
        self.assertIn('Usage:', run.stdout)
        for args in [['--bad'], ['a', 'b', 'c'], ['']]:
            run = subprocess.run([str(BINARY), *args], cwd=self.directory, capture_output=True)
            self.assertEqual(run.returncode, 1)

    def test_missing_input_and_unwritable_database_path(self):
        run = subprocess.run([str(BINARY), 'missing.csv'], cwd=self.directory, capture_output=True)
        self.assertEqual(run.returncode, 1)
        self.source.write_text(document(row()))
        run = subprocess.run([str(BINARY), str(self.source), str(self.directory / 'missing' / 'db')],
                             capture_output=True)
        self.assertEqual(run.returncode, 1)

    @unittest.skipUnless((ROOT / 'isotopes.csv').exists(), 'local IAEA CSV not available')
    def test_every_real_csv_record(self):
        text = (ROOT / 'isotopes.csv').read_text()
        self.run_import(text)
        expected = list(csv.DictReader(io.StringIO(text)))
        actual = {(r['z'], r['n']): r for r in self.records()}
        self.assertEqual(len(actual), len(expected))
        for source in expected:
            key = int(source['z']), int(source['n'])
            record = actual[key]
            self.assertEqual(record['symbol'], source['symbol'])
            self.assertEqual(record['a'], sum(key))
            self.assertEqual(next(csv.reader([record['source_csv']])),
                             [source[key] for key in HEADER])
            seconds = source['half_life_sec']
            if seconds:
                self.assertEqual(record['half_life_seconds'], float(seconds))
                self.assertTrue(math.isclose(record['decay_constant'], math.log(2)/float(seconds), rel_tol=1e-14))
                self.assertEqual(record['status'], 'qualified' if source['operator_hl'] else 'measured')
            elif source['half_life'] == 'STABLE':
                self.assertEqual(record['status'], 'stable')
                self.assertEqual(record['decay_constant'], 0)
            else:
                self.assertEqual(record['status'], 'unknown')
                self.assertIsNone(record['decay_constant'])


if __name__ == '__main__':
    unittest.main()
