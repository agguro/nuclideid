#!/usr/bin/env python3
"""Create reproducible teaching examples; synthetic data, not measurements."""
import csv
import json
import math
from pathlib import Path
import random
import sqlite3

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]


def generate():
    with sqlite3.connect((ROOT/'isotopes.sqlite3').as_uri()+'?mode=ro',uri=True) as db:
        refs={}
        for label,z,n in [('Co-60',27,33),('F-18',9,9),('N-13',7,6)]:
            r=db.execute('SELECT half_life_seconds,decay_constant,status FROM nuclides WHERE z=? AND n=?',(z,n)).fetchone()
            if not r or r[2]!='measured':raise ValueError('Missing measured reference: '+label)
            refs[label]=dict(half_life_seconds=r[0],k=r[1])
    rng=random.Random(31415)
    co=refs['Co-60'];f=refs['F-18'];n=refs['N-13']
    clean=[(3*co['half_life_seconds']*i/50,1000*math.exp(-co['k']*3*co['half_life_seconds']*i/50)) for i in range(51)]
    times=[4*f['half_life_seconds']*i/120 for i in range(121)]
    noisy=[(t,1000*math.exp(-f['k']*t)*math.exp(rng.gauss(0,.01))) for t in times]
    background=[(t,1000*math.exp(-f['k']*t)+200) for t in times]
    mixture=[(t,400*math.exp(-f['k']*t)+600*math.exp(-n['k']*t)) for t in times]
    invalid=[(0,1000),(10,900),(20,0),(30,700)]
    scenarios=[
        ('co60_clean.csv',clean,0,'Co-60','Perfect single exponential; synthetic timestamps span three Co-60 half-lives, not a short physical measurement.'),
        ('f18_noisy.csv',noisy,0,'F-18','Single exponential with seeded multiplicative noise; sigma(log y)=0.01.'),
        ('f18_background.csv',background,2,None,'F-18 decay plus a constant background of 200; outside the current fit model.'),
        ('f18_n13_mixture.csv',mixture,2,None,'Mixture of two decay rates, initial amplitudes 400 (F-18) and 600 (N-13); outside the current model.'),
        ('invalid_zero.csv',invalid,1,None,'Contains y=0; invalid for a log-space fit.'),
    ]
    manifest=dict(data_kind='synthetic teaching examples',seed=31415,time_unit='seconds',
                  intensity_unit='arbitrary positive intensity',references_from_sqlite=refs,cases=[])
    for filename,pairs,code,expected,note in scenarios:
        with (HERE/filename).open('w',newline='') as file:
            writer=csv.writer(file,lineterminator='\n');writer.writerow(['t','y'])
            writer.writerows((format(t,'.17g'),format(y,'.17g')) for t,y in pairs)
        manifest['cases'].append(dict(file=filename,samples=len(pairs),expected_exit=code,
                                      expected_candidate=expected,description=note))
    (HERE/'scenarios.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
    return manifest


if __name__=='__main__':
    for case in generate()['cases']:print(case['file'],case['samples'],'samples')
