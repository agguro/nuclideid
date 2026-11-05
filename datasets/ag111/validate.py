#!/usr/bin/env python3
"""Run the real retained measurements through learn_decay and record results."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import sqlite3
import subprocess
from prepare import HERE,prepare

ROOT=HERE.parents[1]


def parse_fit(text):
    first=text.splitlines()[0]
    result={k:float(v) for k,v in re.findall(r'\b(k|half_life_seconds|log_amplitude|log_rmse|r_squared)=([^\s]+)',first)}
    if len(result)!=5:raise ValueError('Unexpected fitter output')
    return result


def validate(binary,database,gpu=False):
    manifest=prepare()
    before=hashlib.sha256(database.read_bytes()).hexdigest()
    with sqlite3.connect(database.as_uri()+'?mode=ro',uri=True) as db:
        ref=db.execute("SELECT half_life_seconds,decay_constant,status FROM nuclides WHERE z=47 AND n=64").fetchone()
    if not ref or ref[2]!='measured':raise ValueError('Measured Ag-111 reference is missing')
    publication=json.loads((HERE/'workbook-reference.json').read_text())
    report=dict(dataset_doi='10.5281/zenodo.18310004',archive_sha256=manifest['archive_sha256'],
                binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
                database_sha256=before,
                sqlite_reference=dict(nuclide='Ag-111',half_life_seconds=ref[0],half_life_days=ref[0]/86400,k=ref[1]),
                workbook_reference=dict(half_life_days=publication['final_half_life_days'],
                                        standard_uncertainty_days=publication['final_standard_uncertainty_days']),
                method=manifest['method'],model_dependent_corrections_applied=False,detectors={})
    out=HERE/'results';out.mkdir(exist_ok=True)
    for detector,summary in manifest['detectors'].items():
        row=dict(samples=summary['rows'],span_days=summary['span_seconds']/86400,
                 independent_python_fit=summary['independent_python_fit'],runs={})
        expected=summary['independent_python_fit']
        for backend in ['cpu','gpu'] if gpu else ['cpu']:
            command=[str(binary),str(HERE/'derived'/f'{detector.lower()}.csv'),str(database)]
            if backend=='cpu':command.append('--cpu')
            result=subprocess.run(command,capture_output=True,text=True,timeout=60)
            name=f'{backend}-{detector.lower()}.txt'
            (out/name).write_text(result.stdout+(('\nSTDERR:\n'+result.stderr) if result.stderr else ''))
            if result.returncode!=0:raise AssertionError(f'{backend}/{detector} failed: {result.stderr}')
            fit=parse_fit(result.stdout)
            for key in ['k','half_life_seconds','log_amplitude','log_rmse','r_squared']:
                if not math.isclose(fit[key],expected[key],rel_tol=1e-10,abs_tol=1e-13):
                    raise AssertionError((backend,detector,key,fit[key],expected[key]))
            if 'candidate=Ag-111 z=47 n=64 ' not in result.stdout:
                raise AssertionError('Expected Ag-111 among default-tolerance candidates')
            days=fit['half_life_seconds']/86400
            if abs(days-ref[0]/86400)/(ref[0]/86400)>.005:
                raise AssertionError('Half-life differs by >0.5% from SQLite reference')
            row['runs'][backend]=dict(returncode=result.returncode,fit=fit,half_life_days=days,
                candidate_lines=[line for line in result.stdout.splitlines() if line.startswith('candidate=')],
                relative_k_error_to_sqlite=abs(fit['k']-ref[1])/fit['k'],
                half_life_difference_from_workbook_days=days-publication['final_half_life_days'],
                difference_in_workbook_standard_uncertainties=(days-publication['final_half_life_days'])/publication['final_standard_uncertainty_days'],
                output_file=name)
            print(detector,backend,'half-life',format(days,'.10f'),'days; Ag-111 candidate confirmed')
        report['detectors'][detector]=row
    if hashlib.sha256(database.read_bytes()).hexdigest()!=before:raise AssertionError('Database changed')
    report['database_unchanged']=True
    report['conclusion']='Both real detector series pass the basic fitter and include Ag-111 among default-tolerance candidates. This is not reproduction of the researchers\' instrument-corrected precision.'
    (out/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    return report


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary',type=Path,default=ROOT/'release/bin/x86_64/learn_decay/learn_decay')
    parser.add_argument('--database',type=Path,default=ROOT/'isotopes.sqlite3')
    parser.add_argument('--gpu',action='store_true',help='also execute actual CUDA inference')
    args=parser.parse_args()
    validate(args.binary.resolve(),args.database.resolve(),args.gpu)
