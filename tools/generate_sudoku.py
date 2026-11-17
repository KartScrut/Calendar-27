#!/usr/bin/env python3
"""Generates the validated Sudoku library used by TWELVE.

Every puzzle is checked to have exactly one solution, then graded by the
techniques a human needs:
  medium -> solvable with naked + hidden singles only (28-33 clues)
  hard   -> needs locked candidates / naked pairs, or more (<= 28 clues)

Outputs:
  Packages/TwelveCore/Sources/TwelveCore/Resources/puzzles.json  (givens only)
  supabase/seed/sudoku_seed.sql                                  (givens + solutions, server side)
Run:  python3 tools/generate_sudoku.py
"""
import json, random, sys, os

PEERS, UNITS = [], []
for r in range(9): UNITS.append([r*9+c for c in range(9)])
for c in range(9): UNITS.append([r*9+c for r in range(9)])
for b in range(9): UNITS.append([(b//3*3+i)*9+(b%3*3+j) for i in range(3) for j in range(3)])
for i in range(81):
    s=set()
    for u in UNITS:
        if i in u: s.update(u)
    s.discard(i); PEERS.append(sorted(s))

def count_solutions(g, limit=2):
    g=list(g); count=0
    def rec():
        nonlocal count
        best=-1; bc=None
        for i in range(81):
            if g[i]==0:
                used={g[p] for p in PEERS[i]}
                c=[d for d in range(1,10) if d not in used]
                if not c: return
                if bc is None or len(c)<len(bc):
                    best,bc=i,c
                    if len(c)==1: break
        if best<0:
            count+=1; return
        for d in bc:
            g[best]=d; rec(); g[best]=0
            if count>=limit: return
    rec(); return count

def solve(g):
    g=list(g)
    def rec():
        best=-1; bc=None
        for i in range(81):
            if g[i]==0:
                used={g[p] for p in PEERS[i]}
                c=[d for d in range(1,10) if d not in used]
                if not c: return False
                if bc is None or len(c)<len(bc): best,bc=i,c
        if best<0: return True
        for d in bc:
            g[best]=d
            if rec(): return True
            g[best]=0
        return False
    return g if rec() else None

def full_grid(rng):
    g=[0]*81
    def rec(i):
        if i==81: return True
        ds=list(range(1,10)); rng.shuffle(ds)
        used={g[p] for p in PEERS[i]}
        for d in ds:
            if d not in used:
                g[i]=d
                if rec(i+1): return True
                g[i]=0
        return False
    rec(0); return g

def grade(givens):
    """Returns (level, hidden_single_steps). level 1 singles only, 2 needs locked/pairs, 3 beyond."""
    g=list(givens)
    cand=[set() if g[i] else set(range(1,10))-{g[p] for p in PEERS[i]} for i in range(81)]
    level=1; hidden=0
    def place(i,d):
        g[i]=d; cand[i]=set()
        for p in PEERS[i]: cand[p].discard(d)
    while 0 in g:
        progressed=False
        for i in range(81):
            if g[i]==0 and len(cand[i])==1:
                place(i,next(iter(cand[i]))); progressed=True
        if progressed: continue
        for u in UNITS:
            for d in range(1,10):
                spots=[i for i in u if g[i]==0 and d in cand[i]]
                if len(spots)==1:
                    place(spots[0],d); progressed=True; hidden+=1
        if progressed: continue
        # locked candidates (pointing) and naked pairs
        for b in UNITS[18:]:
            for d in range(1,10):
                spots=[i for i in b if g[i]==0 and d in cand[i]]
                if len(spots)>=2:
                    rows={i//9 for i in spots}; cols={i%9 for i in spots}
                    line=None
                    if len(rows)==1: line=UNITS[next(iter(rows))]
                    elif len(cols)==1: line=UNITS[9+next(iter(cols))]
                    if line:
                        for i in line:
                            if i not in b and d in cand[i]:
                                cand[i].discard(d); progressed=True
        for u in UNITS:
            cells=[i for i in u if g[i]==0 and len(cand[i])==2]
            for a in range(len(cells)):
                for b2 in range(a+1,len(cells)):
                    if cand[cells[a]]==cand[cells[b2]]:
                        pair=set(cand[cells[a]])
                        for i in u:
                            if g[i]==0 and i not in (cells[a],cells[b2]) and cand[i]&pair:
                                cand[i]-=pair; progressed=True
        if progressed:
            level=max(level,2); continue
        return 3,hidden
    return level,hidden

def make(rng, want):
    while True:
        sol=full_grid(rng); g=list(sol)
        order=list(range(81)); rng.shuffle(order)
        floor = 30 if want=="medium" else 24
        for i in order:
            if sum(1 for v in g if v)<=floor: break
            j=80-i  # rotational symmetry looks nicer on the board
            bi,bj=g[i],g[j]
            if bi==0: continue
            g[i]=0; g[j]=0
            if count_solutions(g)!=1: g[i],g[j]=bi,bj
        clues=sum(1 for v in g if v)
        level,hidden=grade(g)
        if want=="medium" and level==1 and hidden>=8 and 28<=clues<=33: return g,sol
        if want=="hard" and level==2 and clues<=28: return g,sol

def main():
    rng=random.Random(2027)
    out=[]; seen=set()
    for diff,prefix,n in (("medium","m",20),("hard","h",20)):
        k=0
        while k<n:
            g,sol=make(rng,diff)
            s="".join(map(str,g))
            if s in seen: continue
            assert count_solutions(g)==1 and solve(g)==sol
            seen.add(s); k+=1
            out.append({"id":f"{prefix}{k:02d}","difficulty":diff,"givens":s,"solution":"".join(map(str,sol))})
            print(out[-1]["id"],sum(1 for v in g if v),file=sys.stderr)
    root=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    with open(os.path.join(root,"Packages/TwelveCore/Sources/TwelveCore/Resources/puzzles.json"),"w") as f:
        json.dump([{k:p[k] for k in ("id","difficulty","givens")} for p in out],f,indent=1)
    os.makedirs(os.path.join(root,"supabase/seed"),exist_ok=True)
    with open(os.path.join(root,"supabase/seed/sudoku_seed.sql"),"w") as f:
        f.write("-- Generated by tools/generate_sudoku.py. Do not edit by hand.\n")
        for p in out:
            f.write(f"insert into public.sudoku_puzzles (id, difficulty, givens, puzzle_version) values ('{p['id']}','{p['difficulty']}','{p['givens']}',1) on conflict (id) do nothing;\n")
            f.write(f"insert into private.sudoku_solutions (puzzle_id, solution) values ('{p['id']}','{p['solution']}') on conflict (puzzle_id) do nothing;\n")
main()
