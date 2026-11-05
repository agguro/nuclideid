#!/usr/bin/env python3
"""Optional audit of the archived Excel workbook; requires xlrd==2.0.2.

Only cached measurements/results are read. No spreadsheet formulas/macros run.
The workbook is not an input to the independent primary measurement fit.
"""
import hashlib
import json
from pathlib import Path
import zipfile
import xlrd
from prepare import HERE,load_reports


def inspect():
    raw={r['measurement'].casefold():r for r in load_reports()}
    with zipfile.ZipFile(HERE/'111Ag_half_life.zip') as archive:
        member=next(n for n in archive.namelist() if n.endswith('.xls'))
        content=archive.read(member)
    book=xlrd.open_workbook(file_contents=content)
    data_checks={}
    aliases=[]
    discrepancies=[]
    exact_records={}
    matched_ids=set()
    for detector in ['OR20','OR50']:
        sheet=book.sheet_by_name(f'111Ag 342.1 keV {detector}')
        matched=0
        exact_records[detector]=0
        for i in range(15,sheet.nrows):
            name=sheet.cell_value(i,5)
            if not name:continue
            key=name.removesuffix('.Spc').casefold()
            if key in raw:
                report=raw[key]
            else:
                matches=[r for r in raw.values() if r['detector']==detector
                    and abs(r['peak_area_counts']-sheet.cell_value(i,14))<1e-6
                    and abs(r['live_time_s']-sheet.cell_value(i,11))<1e-6
                    and abs(r['real_time_s']-sheet.cell_value(i,10))<1e-6]
                if len(matches)!=1:raise ValueError(('Cannot cross-match workbook row',detector,i+1,name))
                report=matches[0]
                aliases.append(dict(sheet=sheet.name,row=i+1,workbook_name=name,
                                    report_name=report['measurement'],
                                    match='unique exact peak area, live time, true time; start timestamp checked below'))
            if report['measurement'] in matched_ids:raise ValueError('Duplicate workbook mapping')
            matched_ids.add(report['measurement'])
            exact=True
            for col,field in [(10,'real_time_s'),(11,'live_time_s'),(14,'peak_area_counts')]:
                value=sheet.cell_value(i,col)
                if abs(value-report[field])>1e-6:
                    exact=False
                    discrepancies.append(dict(sheet=sheet.name,row=i+1,measurement=name,
                        field=field,workbook_value=value,report_value=report[field],
                        difference=value-report[field],relative_difference=(value-report[field])/report[field]))
            exact_records[detector]+=int(exact)
            date=xlrd.xldate_as_datetime(sheet.cell_value(i,6)+sheet.cell_value(i,7),book.datemode)
            if abs((date-report['start']).total_seconds())>.001:raise ValueError('timestamp mismatch')
            matched+=1
        data_checks[detector]=matched
    def val(sheet,ref):
        import re
        letters,digits=re.fullmatch(r'([A-Z]+)(\d+)',ref).groups()
        col=0
        for c in letters:col=col*26+ord(c)-64
        return book.sheet_by_name(sheet).cell_value(int(digits)-1,col-1)
    cells=[('Uncertainty','C33'),('Uncertainty','D33'),
           ('Elab (OR20 & OR50)','M15'),('Elab (OR20 & OR50)','N15'),
           ('Elab (OR20)','K11'),('Elab (OR20)','L11'),
           ('Elab (OR50)','K11'),('Elab (OR50)','L11'),
           ('111Ag 342.1 keV OR20','B5'),('111Ag 342.1 keV OR50','B5')]
    result=dict(workbook_archive_member=member,workbook_sha256=hashlib.sha256(content).hexdigest(),
                reader='xlrd '+xlrd.__version__,measurements_cross_checked=data_checks,
                workbook_filename_discrepancies=aliases,
                workbook_report_value_discrepancies=discrepancies,
                exact_numeric_record_matches=exact_records,
                cached_cells=[dict(sheet=s,cell=c,value=val(s,c)) for s,c in cells],
                final_half_life_days=val('Uncertainty','C33'),
                final_standard_uncertainty_days=val('Uncertainty','D33'),
                combined_statistical_fit_half_life_days=val('Elab (OR20 & OR50)','M15'),
                combined_statistical_uncertainty_days=val('Elab (OR20 & OR50)','N15'),
                note='Cached workbook results include instrument corrections and a different regression; they are comparison references, not independent fitter inputs.')
    (HERE/'workbook-reference.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print('Workbook records cross-matched:',data_checks,'exact numeric matches:',exact_records)
    print('Value discrepancies:',len(discrepancies),'filename discrepancies:',len(aliases))
    print('Cached final half-life:',result['final_half_life_days'],'+/-',result['final_standard_uncertainty_days'],'days')


if __name__=='__main__':inspect()
