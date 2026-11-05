#!/usr/bin/env python3
"""Run all synthetic teaching examples plus both retained real Ag-111 series."""
import argparse
import json
from pathlib import Path
import subprocess

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]


def run(gpu=False):
    manifest=json.loads((HERE/'scenarios.json').read_text())
    cases=[{**case,'path':HERE/case['file']} for case in manifest['cases']]
    for detector in ['or20','or50']:
        cases.append(dict(file='real_ag111_'+detector,path=ROOT/'datasets/ag111/derived'/f'{detector}.csv',
                          expected_exit=0,expected_candidate='Ag-111'))
    results=[]
    for case in cases:
        command=[str(ROOT/'release/bin/x86_64/learn_decay/learn_decay'),str(case['path']),str(ROOT/'isotopes.sqlite3')]
        if not gpu:command.append('--cpu')
        result=subprocess.run(command,capture_output=True,text=True,timeout=60)
        if result.returncode!=case['expected_exit']:
            raise AssertionError((case['file'],result.returncode,result.stdout,result.stderr))
        if case['expected_candidate']:
            if 'candidate='+case['expected_candidate']+' ' not in result.stdout:
                raise AssertionError('Expected candidate missing: '+case['file'])
        elif 'candidate=' in result.stdout:
            raise AssertionError('Unexpected match for rejected input: '+case['file'])
        print(case['file']+': expected outcome confirmed (exit '+str(result.returncode)+')')
        results.append(dict(case=case['file'],returncode=result.returncode,stdout=result.stdout,stderr=result.stderr))
    output=HERE/('gpu-results.json' if gpu else 'cpu-results.json')
    output.write_text(json.dumps(dict(backend='GPU' if gpu else 'CPU reference',cases=results),indent=2)+'\n')
    return results


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gpu',action='store_true')
    run(parser.parse_args().gpu)
