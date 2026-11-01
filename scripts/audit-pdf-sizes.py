#!/usr/bin/env python3
"""Measure actual paths and image transforms; not just PDF page boxes. Requires pypdf."""
import json
import math
import sys
from pathlib import Path
from pypdf import PdfReader
from pypdf.generic import ContentStream

MM = 25.4 / 72
IDENTITY = (1, 0, 0, 1, 0, 0)

def multiply(a, b):
    x,y,z,w,u,v=a; A,B,C,D,E,F=b
    return (x*A+z*B, y*A+w*B, x*C+z*D, y*C+w*D, x*E+z*F+u, y*E+w*F+v)

def point(m, x, y):
    a,b,c,d,e,f=m
    return (a*x+c*y+e, b*x+d*y+f)

def measure(path):
    reader=PdfReader(path)
    page=reader.pages[0]
    lines=[]; bars=[]; image_boxes=[]
    def visit(stream, resources, initial=IDENTITY):
        ctm=initial; stack=[]; current=None
        ops=stream.operations if isinstance(stream,ContentStream) else ContentStream(stream,reader).operations
        for args,op in ops:
            if op==b'q':stack.append(ctm)
            elif op==b'Q':ctm=stack.pop()
            elif op==b'cm':ctm=multiply(ctm,tuple(map(float,args)))
            elif op==b'm':current=point(ctm,*map(float,args))
            elif op==b'l':
                end=point(ctm,*map(float,args))
                if current:lines.append((current,end))
                current=end
            elif op==b'Do':
                obj=resources['/XObject'][args[0]].get_object()
                if obj['/Subtype']=='/Form':
                    visit(obj,obj.get('/Resources',resources),multiply(ctm,tuple(map(float,obj.get('/Matrix',IDENTITY)))))
                elif obj['/Subtype']=='/Image':
                    corners=[point(ctm,x,y) for x,y in [(0,0),(1,0),(0,1),(1,1)]]
                    left=min(x for x,y in corners);right=max(x for x,y in corners)
                    bottom=min(y for x,y in corners);top=max(y for x,y in corners)
                    image_boxes.append([left*MM,(float(page.mediabox.height)-top)*MM,(right-left)*MM,(top-bottom)*MM])
                    if obj['/Width']==1000 and obj['/Height']==10:
                        a=point(ctm,0,0);b=point(ctm,1,0)
                        bars.append(math.dist(a,b)*MM)
    visit(page.get_contents(),page['/Resources'])
    vertical=sorted(set(round(a[0]*MM,5) for a,b in lines if abs(a[0]-b[0])<1e-5))
    horizontal=sorted(set(round(a[1]*MM,5) for a,b in lines if abs(a[1]-b[1])<1e-5))
    paper=[float(page.mediabox.width)*MM,float(page.mediabox.height)*MM]
    return {
        'file':str(path),'pages':len(reader.pages),'paper_mm':paper,
        'vertical_cut_x_mm':vertical,'horizontal_cut_from_bottom_mm':horizontal,
        'column_pitches_mm':[round(b-a,5) for a,b in zip(vertical,vertical[1:])],
        'row_pitches_mm':[round(b-a,5) for a,b in zip(horizontal,horizontal[1:])],
        'top_cut_from_top_mm':paper[1]-horizontal[-1] if horizontal else None,
        'reference_bar_widths_mm':bars,'image_boxes_from_top_mm':image_boxes,
    }

if __name__=='__main__':
    directory=Path(sys.argv[1] if len(sys.argv)>1 else 'output/pdf/size-audit')
    result=[measure(p) for p in sorted(directory.glob('*.pdf'))]
    (directory/'measurements.json').write_text(json.dumps(result,indent=2)+'\n')
    for r in result:
        print(Path(r['file']).name,'paper:',[round(n,4) for n in r['paper_mm']],
              'columns:',r['column_pitches_mm'][:2],'rows:',r['row_pitches_mm'][:2],
              'left:',r['vertical_cut_x_mm'][:1],
              'top:',round(r['top_cut_from_top_mm'],4) if r['top_cut_from_top_mm'] is not None else '-',
              'bar:',round(r['reference_bar_widths_mm'][0],4) if r['reference_bar_widths_mm'] else '-')

    by_name={Path(r['file']).name:r for r in result}
    failures=[]
    for name,r in by_name.items():
        if not all(abs(v-50)<0.001 for v in r['reference_bar_widths_mm']): failures.append(name+': reference bar scaled')
        if max(abs(r['paper_mm'][0]-210),abs(r['paper_mm'][1]-297))>0.1: failures.append(name+': non-A4 paper')
        if name.endswith('-system-print.pdf'):
            source=by_name[name.replace('-system-print.pdf','-source.pdf')]
            for key in ['column_pitches_mm','row_pitches_mm','vertical_cut_x_mm']:
                if len(r[key])!=len(source[key]) or any(abs(a-b)>0.001 for a,b in zip(r[key],source[key])):
                    failures.append(name+': '+key+' differs from source')
            if len(r['image_boxes_from_top_mm'])!=len(source['image_boxes_from_top_mm']) or any(
                abs(a-b)>0.001 for actual,expected in zip(r['image_boxes_from_top_mm'],source['image_boxes_from_top_mm'])
                for a,b in zip(actual,expected)):
                failures.append(name+': image placement differs from source')
            if source['top_cut_from_top_mm'] is not None and abs(r['top_cut_from_top_mm']-source['top_cut_from_top_mm'])>0.001:
                failures.append(name+': top origin differs from source')
    if failures:
        raise SystemExit('FAIL: '+'; '.join(failures))
    print('PASS: PDF content geometry, top/left origins, image positions, reference bars where present, and actual-size print output')
