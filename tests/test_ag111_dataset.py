"""Regression checks for the original retained real Ag-111 measurements."""
import csv
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
HERE=ROOT/'datasets/ag111'
spec=importlib.util.spec_from_file_location('ag111_prepare',HERE/'prepare.py')
prepare=importlib.util.module_from_spec(spec);spec.loader.exec_module(prepare)
BINARY=ROOT/'release/bin/x86_64/learn_decay/learn_decay'
DATABASE=ROOT/'isotopes.sqlite3'


class Ag111DatasetTests(unittest.TestCase):
    def test_original_archive_checksum_and_license(self):
        content=(HERE/'111Ag_half_life.zip').read_bytes()
        self.assertEqual(len(content),11317060)
        self.assertEqual(hashlib.md5(content).hexdigest(),prepare.MD5)
        self.assertEqual(hashlib.sha256(content).hexdigest(),prepare.SHA256)
        self.assertEqual(json.loads((HERE/'zenodo-record.json').read_text())['metadata']['license']['id'],'cc-by-4.0')

    def test_every_report_has_valid_measurements(self):
        rows=prepare.load_reports()
        self.assertEqual(len(rows),1082)
        self.assertEqual(len({r['measurement'] for r in rows}),1082)
        self.assertEqual(sum(r['detector']=='OR20' for r in rows),792)
        self.assertEqual(sum(r['detector']=='OR50' for r in rows),290)
        for row in rows:
            self.assertGreater(row['peak_area_counts'],0)
            self.assertGreater(row['live_time_s'],0)
            self.assertLessEqual(row['live_time_s'],row['real_time_s'])

    def test_preparation_is_reproducible(self):
        paths=sorted((HERE/'derived').iterdir())
        before={p.name:hashlib.sha256(p.read_bytes()).digest() for p in paths}
        manifest=prepare.prepare()
        after={p.name:hashlib.sha256(p.read_bytes()).digest() for p in paths}
        self.assertEqual(before,after)
        self.assertEqual(manifest['excluded_reports'],0)
        self.assertFalse(manifest['model_dependent_corrections_applied'])

    def test_independent_regression_and_csv_contract(self):
        for detector,count,days in [('or20',792,7.4334184840090325),('or50',290,7.426450111485696)]:
            with self.subTest(detector=detector):
                with (HERE/'derived'/f'{detector}.csv').open(newline='') as f:
                    reader=csv.DictReader(f)
                    self.assertEqual(reader.fieldnames,['t','y'])
                    pairs=[(float(r['t']),float(r['y'])) for r in reader]
                self.assertEqual(len(pairs),count)
                self.assertEqual(pairs[0][0],0)
                self.assertTrue(all(b[0]>a[0] for a,b in zip(pairs,pairs[1:])))
                fit=prepare.regression(pairs)
                self.assertTrue(math.isclose(fit['half_life_days'],days,rel_tol=1e-12))
                self.assertLess(fit['log_rmse'],.05)
                self.assertGreater(fit['r_squared'],.95)

    def test_workbook_discrepancies_are_retained(self):
        audit=json.loads((HERE/'workbook-reference.json').read_text())
        self.assertEqual(audit['measurements_cross_checked'],{'OR20':792,'OR50':290})
        self.assertEqual(audit['exact_numeric_record_matches'],{'OR20':792,'OR50':251})
        mismatches=audit['workbook_report_value_discrepancies']
        self.assertEqual(len(mismatches),39)
        self.assertTrue(all(r['field']=='peak_area_counts' and 'OR50' in r['sheet'] for r in mismatches))
        self.assertEqual(len(audit['workbook_filename_discrepancies']),1)
        self.assertEqual(audit['workbook_filename_discrepancies'][0]['row'],736)
        self.assertAlmostEqual(audit['final_half_life_days'],7.423603370544002,places=12)

    def test_captured_cpu_gpu_results(self):
        report=json.loads((HERE/'results/report.json').read_text())
        self.assertTrue(report['database_unchanged'])
        for detector,row in report['detectors'].items():
            self.assertIn('cpu',row['runs'])
            for backend in row['runs']:
                with self.subTest(detector=detector,backend=backend):
                    run=row['runs'][backend]
                    self.assertEqual(run['returncode'],0)
                    self.assertEqual(len(run['candidate_lines']),1)
                    self.assertTrue(run['candidate_lines'][0].startswith('candidate=Ag-111 z=47 n=64 '))
                    self.assertLess(run['relative_k_error_to_sqlite'],.01)
                    self.assertTrue(math.isclose(run['fit']['k'],row['independent_python_fit']['k'],rel_tol=1e-11))
                    self.assertGreater(run['difference_in_workbook_standard_uncertainties'],1)

    @unittest.skipUnless(BINARY.exists() and DATABASE.exists(),'build inference and import SQLite first')
    def test_live_cpu_measurements(self):
        self.check_live(False)

    @unittest.skipUnless(os.environ.get('NUCLIDEID_TEST_GPU')=='1' and BINARY.exists() and DATABASE.exists(),
                         'set NUCLIDEID_TEST_GPU=1 with GPU and SQLite catalog available')
    def test_live_gpu_measurements(self):
        self.check_live(True)

    def check_live(self,gpu):
        before=hashlib.sha256(DATABASE.read_bytes()).digest()
        manifest=json.loads((HERE/'derived/preparation.json').read_text())
        for detector in ['OR20','OR50']:
            args=[str(BINARY),str(HERE/'derived'/f'{detector.lower()}.csv'),str(DATABASE)]
            if not gpu:args.append('--cpu')
            result=subprocess.run(args,capture_output=True,text=True,timeout=60)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertIn('candidate=Ag-111 z=47 n=64 ',result.stdout)
            actual=float(result.stdout.split('k=',1)[1].split()[0])
            expected=manifest['detectors'][detector]['independent_python_fit']['k']
            self.assertTrue(math.isclose(actual,expected,rel_tol=1e-11))
        self.assertEqual(hashlib.sha256(DATABASE.read_bytes()).digest(),before)


if __name__=='__main__':unittest.main()
