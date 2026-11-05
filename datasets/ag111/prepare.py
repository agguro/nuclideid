#!/usr/bin/env python3
"""Convert the retained Ag-111 archive to documented measurements; stdlib only.

No rates, time corrections, or selection thresholds are adjusted using our fit
or the published half-life. Every published peak-list report is retained.
"""
import csv
from datetime import datetime, timedelta
import hashlib
import json
import math
from pathlib import Path
import re
import zipfile

HERE = Path(__file__).resolve().parent
ARCHIVE = HERE / '111Ag_half_life.zip'
MD5 = '760fa6811cc571f2b568089a0139b17a'
SHA256 = 'b8752cd29dd48e6401bd0f53c753f18810d105c37d5c3fd7b7fc468eb90533e7'
MONTHS = dict(zip('gen feb mar apr mag giu lug ago set ott nov dic'.split(),range(1,13)))
EXPECTED_COUNTS = {'OR20':792,'OR50':290}


def parse_stamp(text):
    match=re.fullmatch(r'(\d{4})-([a-z]{3})-(\d{2}) (\d{2}):(\d{2}):(\d{2})',text)
    if not match:raise ValueError(f'Unexpected timestamp: {text!r}')
    year,month,day,hour,minute,second=match.groups()
    return datetime(int(year),MONTHS[month],int(day),int(hour),int(minute),int(second))


def parse_report(member,contents):
    text=contents.decode('cp1252')
    fields={}
    for line in text.splitlines():
        cells=line.split('\t')
        if len(cells)>1:fields.setdefault(cells[0],cells[1])
    detector=re.search(r'/Gamma_Spectra/(OR\d+)/Peak lists files/',member)
    if not detector:raise ValueError(f'Unexpected report location: {member}')
    detector=detector.group(1)
    if detector not in EXPECTED_COUNTS:raise ValueError(detector)
    start=parse_stamp(fields['START DATE'])
    end=parse_stamp(fields['END DATE'])
    live=float(fields['LIVETIME'].removesuffix(' sec'))
    real=float(fields['TRUETIME'].removesuffix(' sec'))
    if not all(math.isfinite(v) and v>0 for v in [live,real]) or live>real:
        raise ValueError(f'Invalid live/real time: {member}')
    # Exported START/END timestamps have whole-second precision.
    if abs((end-start).total_seconds()-real)>2:
        raise ValueError(f'Start/end/true time disagree: {member}')
    peak_section=text.split('List of peaks',1)[1]
    expected_header=['Pk #','Region [ch]','RXSQ','Pos [ch]','E [keV]',
                     'E unc [keV]','Area [cnt]','Area unc [%]','FWHM [ch]']
    if not any(line.split('\t')[:9]==expected_header for line in peak_section.splitlines()):
        raise ValueError(f'Unexpected peak-table columns: {member}')
    peaks=[]
    for line in peak_section.splitlines():
        cells=line.split('\t')
        if len(cells)>=9 and cells[0].isdigit():
            energy,area,unc=float(cells[4]),float(cells[6]),float(cells[7])
            if abs(energy-342.1)<1:
                peaks.append((energy,area,unc))
    if len(peaks)!=1:raise ValueError(f'Ambiguous/missing 342.1-keV peak: {member}')
    energy,area,unc=peaks[0]
    if not all(math.isfinite(v) and v>0 for v in [energy,area,unc]):
        raise ValueError(f'Invalid peak values: {member}')
    return dict(detector=detector,measurement=fields['EXPORT FILE NAME'],
                archive_member=member,start=start,end=end,
                midpoint=start+timedelta(seconds=real/2),
                real_time_s=real,live_time_s=live,peak_energy_keV=energy,
                peak_area_counts=area,area_unc_percent=unc,rate_per_live_s=area/live)


def load_reports():
    content=ARCHIVE.read_bytes()
    if hashlib.md5(content).hexdigest()!=MD5 or hashlib.sha256(content).hexdigest()!=SHA256:
        raise ValueError('Original archive checksum mismatch')
    with zipfile.ZipFile(ARCHIVE) as archive:
        rows=[parse_report(name,archive.read(name)) for name in sorted(archive.namelist())
              if name.endswith('.TXT')]
    if len({r['measurement'] for r in rows})!=len(rows):raise ValueError('Duplicate measurement IDs')
    for detector,count in EXPECTED_COUNTS.items():
        if sum(r['detector']==detector for r in rows)!=count:
            raise ValueError(f'Wrong report count for {detector}')
    return rows


def regression(pairs):
    """Independent centered log-linear regression with math.fsum reductions."""
    x=[t for t,y in pairs];v=[math.log(y) for t,y in pairs];n=len(pairs)
    mx=math.fsum(x)/n;mv=math.fsum(v)/n
    sxx=math.fsum((a-mx)**2 for a in x)
    sxv=math.fsum((a-mx)*(b-mv) for a,b in zip(x,v))
    syy=math.fsum((b-mv)**2 for b in v)
    slope=sxv/sxx;k=-slope
    sse=math.fsum((b-mv-slope*(a-mx))**2 for a,b in zip(x,v))
    return dict(k=k,half_life_seconds=math.log(2)/k,half_life_days=math.log(2)/k/86400,
                log_amplitude=mv-slope*mx,log_rmse=math.sqrt(sse/n),r_squared=1-sse/syy)


def prepare():
    rows=load_reports()
    out=HERE/'derived';out.mkdir(exist_ok=True)
    manifest=dict(archive=ARCHIVE.name,archive_md5=MD5,archive_sha256=SHA256,
                  target_peak_keV=342.1,selection_window_keV=1.0,
                  input_reports=len(rows),excluded_reports=0,
                  method='t=acquisition midpoint relative to first midpoint; y=net photopeak area/live seconds',
                  model_dependent_corrections_applied=False,detectors={})
    audit=[]
    for detector,count in EXPECTED_COUNTS.items():
        group=sorted((r for r in rows if r['detector']==detector),key=lambda r:r['midpoint'])
        first=group[0]['midpoint']
        pairs=[((r['midpoint']-first).total_seconds(),r['rate_per_live_s']) for r in group]
        if any(b[0]<=a[0] for a,b in zip(pairs,pairs[1:])):raise ValueError('Nonincreasing times')
        file=out/f'{detector.lower()}.csv'
        with file.open('w',newline='') as f:
            writer=csv.writer(f,lineterminator='\n');writer.writerow(['t','y'])
            writer.writerows((format(t,'.17g'),format(y,'.17g')) for t,y in pairs)
        for r,(t,y) in zip(group,pairs):
            audit.append({**r,'elapsed_midpoint_s':t})
        manifest['detectors'][detector]=dict(rows=count,first_start=group[0]['start'].isoformat(),
            last_start=group[-1]['start'].isoformat(),span_seconds=pairs[-1][0],
            input_sha256=hashlib.sha256(file.read_bytes()).hexdigest(),
            real_time_range_s=[min(r['real_time_s'] for r in group),max(r['real_time_s'] for r in group)],
            dead_time_fraction_range=[min(1-r['live_time_s']/r['real_time_s'] for r in group),
                                      max(1-r['live_time_s']/r['real_time_s'] for r in group)],
            independent_python_fit=regression(pairs))
    names=['detector','measurement','archive_member','start','end','midpoint',
           'elapsed_midpoint_s','real_time_s','live_time_s','peak_energy_keV',
           'peak_area_counts','area_unc_percent','rate_per_live_s']
    with (out/'measurements.csv').open('w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=names,lineterminator='\n');writer.writeheader()
        for record in audit:
            writer.writerow({k:(v.isoformat() if isinstance(v,datetime) else format(v,'.17g') if isinstance(v,float) else v)
                             for k,v in record.items()})
    (out/'preparation.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
    return manifest


if __name__=='__main__':
    result=prepare()
    for name,detector in result['detectors'].items():
        print(name,detector['rows'],'samples; Python half-life:',
              detector['independent_python_fit']['half_life_days'],'days')
