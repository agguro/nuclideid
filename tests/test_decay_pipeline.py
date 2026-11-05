"""Independent numeric oracles and CLI integration tests; GPU tests opt in.

NUCLIDEID_TEST_GPU=1 enables execution on actual NVIDIA hardware. CPU-only tests
never initialize CUDA. All files are confined to temporary directories.
"""
import csv
import ctypes as C
import hashlib
import io
import math
import os
from pathlib import Path
import random
import re
import sqlite3
import shutil
import subprocess
import sys
import tempfile
import unittest

LEARN = Path(sys.argv.pop(1)).resolve()
GENERATE = Path(sys.argv.pop(1)).resolve()
LIB = C.CDLL(str(Path(sys.argv.pop(1)).resolve()))
ROOT = Path(__file__).resolve().parents[1]
GPU = os.environ.get('NUCLIDEID_TEST_GPU') == '1'


class Work(C.Structure):
    _fields_ = [('data', C.POINTER(C.c_double)), ('count', C.c_size_t),
                ('t0', C.c_double), ('span', C.c_double), ('log_y0', C.c_double)]


class Fit(C.Structure):
    _fields_ = [('k', C.c_double), ('half', C.c_double), ('log_a', C.c_double),
                ('rmse', C.c_double), ('r2', C.c_double)]


LIB.decay_parse_number.argtypes = [C.c_char_p, C.POINTER(C.c_double)]
LIB.decay_parse_number.restype = C.c_int
LIB.decay_prepare.argtypes = [C.POINTER(Work)]
LIB.decay_prepare.restype = C.c_int
LIB.decay_moments_cpu.argtypes = [C.POINTER(Work), C.POINTER(C.c_double)]
LIB.decay_moments_cpu.restype = None
LIB.decay_finish.argtypes = [C.POINTER(Work), C.POINTER(C.c_double), C.POINTER(Fit)]
LIB.decay_finish.restype = C.c_int


def curve(k=.25, count=51, span=None, amplitude=1, start=0):
    if span is None: span = 3/k
    return [(start + span*i/(count-1), amplitude*math.exp(-k*span*i/(count-1)))
            for i in range(count)]


def oracle(pairs):
    # Independent Python centered regression with accurate math.fsum reductions.
    ts = [p[0] for p in pairs]
    ys = [math.log(p[1]) for p in pairs]
    tmean, ymean = math.fsum(ts)/len(ts), math.fsum(ys)/len(ys)
    sxx = math.fsum((x-tmean)**2 for x in ts)
    sxy = math.fsum((x-tmean)*(y-ymean) for x,y in zip(ts,ys))
    slope = sxy/sxx
    residual = [y-ymean-slope*(x-tmean) for x,y in zip(ts,ys)]
    sse = math.fsum(e*e for e in residual)
    syy = math.fsum((y-ymean)**2 for y in ys)
    return -slope, ymean-slope*tmean, math.sqrt(sse/len(ts)), 1-sse/syy


def parse_fit(output):
    return {key: float(value) for key,value in re.findall(
        r'\b(k|half_life_seconds|log_amplitude|log_rmse|r_squared)=([^\s]+)', output.splitlines()[0])}


class DecayTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='nuclideid-decay-test-')
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        self.csv = self.directory/'decay_data.csv'
        self.db = self.directory/'isotopes.sqlite3'
        self.create_db([('H',1,2,.25)])

    def create_db(self, candidates):
        if self.db.exists(): self.db.unlink()
        with sqlite3.connect(self.db) as db:
            db.execute('CREATE TABLE nuclides(z,n,a,symbol,half_life_seconds,decay_constant,status)')
            db.executemany('INSERT INTO nuclides VALUES(?,?,?,?,?,?,?)',
                           [(z,n,z+n,s,math.log(2)/k,k,'measured') for s,z,n,k in candidates])

    def write_pairs(self,pairs,ending='\n'):
        with self.csv.open('w',newline='') as f:
            w=csv.writer(f,lineterminator=ending)
            w.writerow(['t','y']);w.writerows(pairs)

    def run_learn(self, gpu=False, tolerance='1e-8', expected=0, extra=()):
        args=[str(LEARN),str(self.csv),str(self.db),'--tolerance',tolerance,*extra]
        if not gpu: args.append('--cpu')
        result=subprocess.run(args,cwd=self.directory,capture_output=True,text=True,timeout=60)
        self.assertEqual(result.returncode,expected,result.stdout+result.stderr)
        return result

    def run_generator(self,k=.25,count=51,span=20,gpu=False,expected=0):
        args=[str(GENERATE),str(k),str(count),str(span),'-o',str(self.csv)]
        if not gpu: args.append('--cpu')
        result=subprocess.run(args,cwd=self.directory,capture_output=True,text=True,timeout=60)
        self.assertEqual(result.returncode,expected,result.stdout+result.stderr)
        if expected:return result
        with self.csv.open(newline='') as f:
            return [(float(r['t']),float(r['y'])) for r in csv.DictReader(f)]

    def fit_api(self,pairs):
        data=(C.c_double*(2*len(pairs)))(*(v for pair in pairs for v in pair))
        work=Work(data,len(pairs),0,0,0)
        self.assertEqual(LIB.decay_prepare(C.byref(work)),0)
        stats=(C.c_double*5)()
        LIB.decay_moments_cpu(C.byref(work),stats)
        fit=Fit()
        self.assertEqual(LIB.decay_finish(C.byref(work),stats,C.byref(fit)),0)
        return fit

    def test_decimal_parser(self):
        for text,value in [('0',0),('.00',0),('-.5',-.5),('+1.2e-8',1.2e-8),('1E20',1e20)]:
            out=C.c_double(99)
            self.assertEqual(LIB.decay_parse_number(text.encode(),C.byref(out)),0)
            self.assertEqual(out.value,value)
        for text in ['', '.', 'NaN', 'inf', '0x1p1', ' 2', '2 ', '1e', '1e309', '1e-999', '2garbage']:
            out=C.c_double(99)
            self.assertEqual(LIB.decay_parse_number(text.encode(),C.byref(out)),1)
            self.assertEqual(out.value,99)

    def test_cpu_fit_wide_decay_scales_and_amplitudes(self):
        for k in [1e-25,1e-12,.25,1e3,8e21]:
            for amplitude in [1e-100,1,1e100]:
                with self.subTest(k=k,amplitude=amplitude):
                    fit=self.fit_api(curve(k=k,count=257,amplitude=amplitude))
                    self.assertTrue(math.isclose(fit.k,k,rel_tol=1e-11))
                    self.assertAlmostEqual(fit.log_a,math.log(amplitude),places=10)
                    self.assertLess(fit.rmse,1e-11)
                    self.assertAlmostEqual(fit.r2,1,places=12)

    def test_shifted_time_origin(self):
        k=.25;start=1e8
        fit=self.fit_api(curve(k=k,start=start,amplitude=7))
        self.assertTrue(math.isclose(fit.k,k,rel_tol=1e-9))
        self.assertTrue(math.isclose(fit.log_a,math.log(7)+k*start,rel_tol=1e-9))

    def test_noisy_fit_matches_independent_oracle(self):
        rng=random.Random(23)
        pairs=[(t,30*y*math.exp(rng.gauss(0,.005))) for t,y in curve(count=513)]
        expected=oracle(pairs);fit=self.fit_api(pairs)
        for actual,want in zip([fit.k,fit.log_a,fit.rmse,fit.r2],expected):
            self.assertTrue(math.isclose(actual,want,rel_tol=1e-10,abs_tol=1e-12),(actual,want))
        self.write_pairs(pairs)
        self.run_learn(tolerance='.01')

    def test_real_count_and_correct_candidate(self):
        for count in [3,7,50,255,256,257,513,4097]:
            with self.subTest(count=count):
                self.write_pairs(curve(count=count))
                result=self.run_learn()
                self.assertIn('candidate=H-3 z=1 n=2',result.stdout)
                self.assertIn(f'samples={count}',result.stdout)
                self.assertTrue(math.isclose(parse_fit(result.stdout)['k'],.25,rel_tol=1e-12))

    def test_every_sample_influences_fit(self):
        pairs=curve(count=257)
        changed=[pairs[0]]+[(t,y*math.exp(-.1*t)) for t,y in pairs[1:]]
        self.write_pairs(changed)
        result=self.run_learn(expected=2)
        self.assertTrue(math.isclose(parse_fit(result.stdout)['k'],.35,rel_tol=1e-12))
        self.assertNotIn('candidate=',result.stdout)

    def test_ambiguous_candidates_reported(self):
        self.create_db([('H',1,2,.25),('He',2,2,.25),('Li',3,3,.251)])
        self.write_pairs(curve())
        result=self.run_learn(tolerance='.01')
        self.assertIn('3 candidate(s)',result.stdout)
        self.assertEqual(result.stdout.count('candidate='),3)
        self.assertIn('does not establish identity',result.stdout)

    def test_out_of_range_has_no_forced_match(self):
        for k in [.001,100]:
            self.write_pairs(curve(k=k))
            result=self.run_learn(expected=2)
            self.assertNotIn('candidate=',result.stdout)
            self.assertIn('no measured isotope',result.stderr)

    def test_flat_and_growing_measurements_rejected(self):
        for pairs in [[(i,1) for i in range(10)],[(i,math.exp(i*.1)) for i in range(10)]]:
            self.write_pairs(pairs)
            result=self.run_learn(expected=1)
            self.assertNotIn('candidate=',result.stdout)

    def test_bad_fit_quality_rejected(self):
        pairs=[(i, math.exp(-.25*i + (.5 if i%2 else -.5))) for i in range(51)]
        self.write_pairs(pairs)
        result=self.run_learn(expected=2)
        self.assertIn('fit rejected',result.stderr)
        self.assertNotIn('candidate=',result.stdout)

    def test_invalid_samples(self):
        for pairs in [[(0,1),(1,0),(2,.5)],[(0,1),(1,-.1),(2,.5)],
                      [(0,1),(1,.7),(1,.5)],[(-1,1),(0,.7),(1,.5)],
                      [(2,1),(1,.7),(3,.5)],[(0,1),(1,float('inf')),(2,.5)],
                      [(0,1),(1,float('nan')),(2,.5)]]:
            self.write_pairs(pairs)
            result=self.run_learn(expected=1)
            self.assertNotIn('candidate=',result.stdout)

    def test_bad_csv_and_header(self):
        for text in ['', 'x,y\n0,1\n1,.7\n2,.5\n','t,y\n0,1\n',
                     't,y\n0,1,extra\n1,.7\n2,.5\n','t,y\n0,1\n1,\n2,.5\n',
                     't,y\n0,1\n1,0.7bad\n2,.5\n',
                     't,y\n0,1\n1,0.7\0\n2,.5\n']:
            self.csv.write_bytes(text.encode())
            self.run_learn(expected=1)

    def test_crlf_empty_lines_and_no_final_newline(self):
        self.write_pairs(curve(),ending='\r\n')
        self.csv.write_bytes(self.csv.read_bytes().rstrip(b'\r\n'))
        self.run_learn()
        self.write_pairs(curve())
        self.csv.write_bytes(self.csv.read_bytes()+b'\n\n')
        self.run_learn()

    def test_read_only_files_and_no_bin_artifacts(self):
        self.write_pairs(curve())
        before={p.name:hashlib.sha256(p.read_bytes()).digest() for p in self.directory.iterdir()}
        self.csv.chmod(0o444);self.db.chmod(0o444)
        self.run_learn()
        after={p.name:hashlib.sha256(p.read_bytes()).digest() for p in self.directory.iterdir()}
        self.assertEqual(before,after)

    def test_generator_cpu_matches_exp(self):
        for k,count,span in [(.25,3,20),(.25,257,20),(1e-20,513,1e20),(1000,51,.7)]:
            pairs=self.run_generator(k,count,span)
            self.assertEqual(len(pairs),count)
            self.assertEqual(pairs[0],(0,1))
            self.assertEqual(pairs[-1][0],span)
            for t,y in pairs:
                self.assertTrue(math.isclose(y,math.exp(-k*t),rel_tol=2e-15))

    def test_generator_to_inference_round_trip(self):
        self.run_generator()
        self.run_learn()
        self.assertFalse(list(self.directory.glob('*.bin')))

    def test_generator_failures_preserve_output(self):
        for k,count,span in [(-1,51,1),(0,51,1),(.25,2,1),(.25,1000001,1),(.25,51,0),
                             (1,51,701),('garbage',51,1),('NaN',51,1)]:
            self.csv.write_text('existing data\n')
            self.run_generator(k,count,span,expected=1)
            self.assertEqual(self.csv.read_text(),'existing data\n')
            self.assertFalse(list(self.directory.glob('*.tmp.*')))

    def test_help_and_bad_options(self):
        for binary in [LEARN,GENERATE]:
            self.assertEqual(subprocess.run([str(binary),'--help'],capture_output=True).returncode,0)
        for args in [['--bad'],['--tolerance'],['--tolerance','0'],['--tolerance','NaN'],
                     ['--tolerance','1.1'],['--cpu','--cpu'],['a','b','c']]:
            self.assertEqual(subprocess.run([str(LEARN),*args],cwd=self.directory,capture_output=True).returncode,1)
        for args in [['.25','51','1','--bad'],['.25','51','1','-o'],['.25','51','1','--cpu','--cpu']]:
            self.assertEqual(subprocess.run([str(GENERATE),*args],cwd=self.directory,capture_output=True).returncode,1)

    def test_missing_source_or_database(self):
        self.run_learn(expected=1)
        self.write_pairs(curve())
        self.db.unlink()
        self.run_learn(expected=1)
        self.assertFalse(self.db.exists())

    @unittest.skipUnless((ROOT/'isotopes.sqlite3').exists(),'real catalog not available')
    def test_real_sqlite_isotopes(self):
        source=ROOT/'isotopes.sqlite3'
        self.db.write_bytes(source.read_bytes())
        with sqlite3.connect(self.db) as db:
            refs=[db.execute('SELECT decay_constant FROM nuclides WHERE z=? AND n=?',(z,n)).fetchone()[0]
                  for z,n in [(27,33),(9,9),(92,146),(1,4)]]
        for k in refs:
            self.write_pairs(curve(k=k,count=257))
            result=self.run_learn()
            self.assertTrue(math.isclose(parse_fit(result.stdout)['k'],k,rel_tol=1e-11))
            self.assertGreaterEqual(result.stdout.count('candidate='),1)

    def preload_stub(self, source):
        cfile=self.directory/'fault.c'
        sofile=self.directory/'fault.so'
        cfile.write_text(source)
        subprocess.run(['gcc','-shared','-fPIC',str(cfile),'-o',str(sofile)],check=True,capture_output=True)
        return dict(os.environ,LD_PRELOAD=str(sofile))

    @unittest.skipUnless(shutil.which('gcc'),'gcc required for driver fault injection')
    def test_no_silent_gpu_fallback_and_output_preserved(self):
        env=self.preload_stub('int cuInit(unsigned int flags) { return 100; }')
        self.write_pairs(curve())
        before=self.csv.read_bytes()
        result=subprocess.run([str(LEARN),str(self.csv),str(self.db)],env=env,capture_output=True,text=True)
        self.assertEqual(result.returncode,1)
        self.assertIn('CUDA error 100',result.stderr)
        self.assertNotIn('candidate=',result.stdout)
        result=subprocess.run([str(GENERATE),'.25','51','20','-o',str(self.csv)],env=env,capture_output=True,text=True)
        self.assertEqual(result.returncode,1)
        self.assertEqual(self.csv.read_bytes(),before)

    @unittest.skipUnless(shutil.which('gcc'),'gcc required for write fault injection')
    def test_generator_write_failures_preserve_output(self):
        env=self.preload_stub('int fputs(const char *text, void *file) { return -1; }')
        self.csv.write_text('existing measurements\n')
        result=subprocess.run([str(GENERATE),'.25','51','20','--cpu','-o',str(self.csv)],env=env,capture_output=True)
        self.assertEqual(result.returncode,1)
        self.assertEqual(self.csv.read_text(),'existing measurements\n')
        self.assertFalse(list(self.directory.glob('*.tmp.*')))

    @unittest.skipUnless(GPU and shutil.which('gcc'),'requires GPU and gcc for copy fault injection')
    def test_gpu_copy_failure_is_reported(self):
        env=self.preload_stub('int cuMemcpyDtoH_v2(void *dst, unsigned long src, unsigned long size) { return 999; }')
        self.write_pairs(curve())
        before=self.csv.read_bytes()
        result=subprocess.run([str(LEARN),str(self.csv),str(self.db)],env=env,capture_output=True,text=True)
        self.assertEqual(result.returncode,1)
        self.assertIn('CUDA error 999',result.stderr)
        self.assertNotIn('candidate=',result.stdout)
        result=subprocess.run([str(GENERATE),'.25','51','20','-o',str(self.csv)],env=env,capture_output=True,text=True)
        self.assertEqual(result.returncode,1)
        self.assertEqual(self.csv.read_bytes(),before)

    @unittest.skipUnless(GPU,'set NUCLIDEID_TEST_GPU=1 to run on NVIDIA hardware')
    def test_gpu_generator_against_independent_exp(self):
        for k,count,span in [(.25,3,20),(.25,255,20),(.25,256,20),(.25,257,20),
                             (1e-20,513,1e20),(1000,4097,.7)]:
            with self.subTest(k=k,count=count):
                pairs=self.run_generator(k,count,span,gpu=True)
                self.assertEqual(len(pairs),count)
                self.assertEqual(pairs[0],(0,1))
                self.assertEqual(pairs[-1][0],span)
                for t,y in pairs:
                    self.assertTrue(math.isclose(y,math.exp(-k*t),rel_tol=2e-12),(t,y,math.exp(-k*t)))

    @unittest.skipUnless(GPU,'set NUCLIDEID_TEST_GPU=1 to run on NVIDIA hardware')
    def test_gpu_fit_matches_cpu_and_python(self):
        rng=random.Random(8)
        for k,count,amplitude in [(.25,3,1),(.25,255,7),(.25,256,1),(.25,257,1),
                                  (1e-25,513,1e-100),(8e21,4097,1e100),(.25,65537,3)]:
            with self.subTest(k=k,count=count):
                self.create_db([('H',1,2,k)])
                pairs=[(t,y*math.exp(rng.gauss(0,.00001))) for t,y in curve(k,count,amplitude=amplitude)]
                self.write_pairs(pairs)
                cpu=self.run_learn(tolerance='.01')
                gpu=self.run_learn(gpu=True,tolerance='.01')
                self.assertIn('backend=GPU',gpu.stdout)
                cf,gf=parse_fit(cpu.stdout),parse_fit(gpu.stdout)
                for key in cf:
                    self.assertTrue(math.isclose(cf[key],gf[key],rel_tol=1e-8,abs_tol=1e-10),(key,cf[key],gf[key]))
                self.assertTrue(math.isclose(gf['k'],oracle(pairs)[0],rel_tol=1e-10))

    @unittest.skipUnless(GPU,'set NUCLIDEID_TEST_GPU=1 to run on NVIDIA hardware')
    def test_gpu_generator_to_gpu_inference(self):
        self.run_generator(count=513,gpu=True)
        result=self.run_learn(gpu=True)
        self.assertIn('candidate=H-3',result.stdout)
        self.assertTrue(math.isclose(parse_fit(result.stdout)['k'],.25,rel_tol=1e-11))

    @unittest.skipUnless(GPU and (ROOT/'isotopes.sqlite3').exists(),'requires GPU and real catalog')
    def test_gpu_real_co60(self):
        self.db.write_bytes((ROOT/'isotopes.sqlite3').read_bytes())
        with sqlite3.connect(self.db) as db:
            k=db.execute('SELECT decay_constant FROM nuclides WHERE z=27 AND n=33').fetchone()[0]
        self.run_generator(k,257,3/k,gpu=True)
        result=self.run_learn(gpu=True)
        self.assertIn('candidate=Co-60 z=27 n=33',result.stdout)
        self.assertTrue(math.isclose(parse_fit(result.stdout)['k'],k,rel_tol=1e-11))


if __name__=='__main__':unittest.main()
