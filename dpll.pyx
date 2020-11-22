#cython: language_level=3
# cython: profile=False

cdef class CNF:
    cdef set vs
    cdef list cs0
    cdef set cs
    cdef dict contains

    def __init__(self, n_vars, nss):
        cdef:
            list vs
            Clause c
            int v
        self.vs = set(range(1, n_vars+1))
        self.cs0 = [Clause(ns) for ns in nss] # includes trivial clauses
        self.cs = set(c for c in self.cs0 if not c.trivial) # excludes trivial clauses
        self.contains = {v: set([c for c in self.cs if v in c]) for v in self.vs} # clauses that contain v

    def __str__(self):
        cdef str meta = "p cnf {} {}".format(len(self.vs), len(self.cs0))
        return "\n".join([meta] + [str(c) + " 0" for c in self.cs0])
    
    cdef list free_vars(self, Model m):
        """Return the list of free variables (those that are not in model m)"""
        cdef int v
        return [v for v in self.vs if v not in m]
    
    cdef bint modeled_by(self, Model m):
        """Check if the CNF formula is modeled by m"""
        cdef Clause c
        return all((c.modeled_by(m) for c in self.cs))
    
    cdef unit_prop(self, Model m, Literal l, Clause c):
        """Do unit-propagation on literal l in clause c"""
        m.commit(l) # declare literal l to be true in model m
        c.trivial = True
        self.cs.remove(c)
    
    def dpll(self):
        cdef:
            Model m = Model()
            bint sat # is the current CNF formula satisfied by model m?
            list free # free variables
            list up # unit-prop variables
            int v
            Clause c

        while True:
            free = self.free_vars(m)
            sat = self.modeled_by(m)
            # check if we're done
            if len(free) == 0:
                if sat:
                    return True
                if len(m.dv) == 0 and not sat:
                    return False
            # if not done, we either need to backtrack, or can branch on a free variable
            if len(m.dv) > 0 and not sat:
                m.backtrack()
            else: # otherwise, there has to be a free var (by logic)
                up = list() # unit-prop var
                for v in free:
                    for c in self.contains[v]:
                        if not c.modeled_by_modulo(m, v):
                            up.append((v, c))
                            break
                if len(up) == 0:
                    m.guess(free[0]) # mark the first free var as decision var
                else:
                    for v, c in up:
                        self.unit_prop(m, c[v], c)


cdef class Literal:
    cdef:
        readonly int var # positive integer representing the variable name
        bint is_pos
        bint is_neg
        int n # +var or -var
    
    def __init__(self, int n):
        self.n = n
        self.var = abs(n)
        self.is_pos = n > 0
        self.is_neg = n < 0

    def __str__(self):
        return str(self.n)
    
    def __eq__(self, Literal other):
        return self.n == other.n
    
    def __hash__(self):
        return self.n


cdef class Clause:
    cdef:
        readonly bint trivial
        set ls

    def __init__(self, list ns):
        """ns - a list of integers representing literals"""
        cdef int n
        self.ls = set() # literals
        self.trivial = False
        for n in ns:
            # check if both n and -n are present
            if Literal(-n) in self.ls:
                self.trivial = True
            self.ls.add(Literal(n))

    def __str__(self):
        cdef Literal l
        return " ".join([str(l) for l in self.ls])
    
    def __contains__(self, l):
        if type(l) == Literal:
            return l in self.ls
        else: # otherwise, l is a variable
            return Literal(l) in self.ls or Literal(-l) in self.ls
    
    def __getitem__(self, int v):
        """Return the literal that contains v in this clause"""
        cdef Literal pos = Literal(v)
        cdef Literal neg = Literal(-v)
        if pos in self.ls:
            return pos
        elif neg in self.ls:
            return neg
        else:
            raise IndexError
    
    def modeled_by(self, Model m):
        """Determine if clause c can be modeled by m"""
        cdef Literal l
        # m can always model clause c if c contains free vars not captured by m
        return any((l not in m or m[l] for l in self.ls))
    
    def modeled_by_modulo(self, Model m, int v):
        """Determine if clause c could be modeled by m if variable v were absent"""
        cdef Literal l
        return any((l not in m or m[l] for l in self.ls if l.var != v))


cdef class Model:
    cdef:
        readonly list dv # decision variables
        dict alpha # assignment function

    def __init__(self):
        self.dv = list()
        self.alpha = dict()
    
    def __contains__(self, l):
        if type(l) == Literal:
            return l.var in self.alpha
        else: # otherwise, l is a variable
            return l in self.alpha
    
    def __getitem__(self, Literal l):
        """Return the truth value of literal l under this model"""
        return l.is_neg ^ self.alpha[l.var]
    
    def commit(self, Literal l):
        """Set literal l to true"""
        self.alpha[l.var] = l.is_pos
    
    def guess(self, int v):
        """Mark v as decison variable, and guess it's True"""
        self.alpha[v] = True
        self.dv.append(v)
    
    def backtrack(self):
        """Backtrack the latest decision variable and take the other branch"""
        cdef int v = self.dv.pop() # v becomes decided
        self.alpha[v] = not self.alpha[v] # guess the remaining option
        return v
    
    def __str__(self):
        cdef:
            int v
            str postfix = lambda v: "_d" if v in self.dv else ""
        if len(self.alpha) > 0:
            return ", ".join(["{}{}: {}".format(v, postfix(v), self.alpha[v]) \
                for v in self.alpha])
        else:
            return "(empty model)"