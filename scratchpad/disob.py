import sys
sys.path.insert(0,'cli/src')
from bakbuild import omf
from capstone import CS_ARCH_X86, CS_MODE_16, Cs
obj = omf.parse('work/ref/CBENC.OBJ')
segs = omf.extract_code_segments(obj)
# build public offset map per segment
md = Cs(CS_ARCH_X86, CS_MODE_16)
target = sys.argv[1] if len(sys.argv)>1 else None
for seg in segs:
    pubs = {p.offset:p.name for p in obj.publics if obj.segments[p.segment_idx-1].name==seg.name}
    # find function ranges
    data = seg.data
    # map fixups offset->name
    fx={}
    for f in seg.fixups:
        fx[f.offset_in_segment]=getattr(f,'target_name',None) or ''
    cur=None
    for insn in md.disasm(data,0):
        if insn.address in pubs:
            cur=pubs[insn.address]
            print('\n=== %s (seg %s off %#x) ==='%(cur,seg.name,insn.address))
        if target and (cur is None or target.lower() not in cur.lower()):
            continue
        fxs=''
        for k in range(insn.address, insn.address+len(insn.bytes)):
            if k in fx: fxs=' ; -> '+fx[k]
        print('%04x: %-20s %s%s'%(insn.address,' '.join('%02x'%b for b in insn.bytes),insn.mnemonic+' '+insn.op_str,fxs))
