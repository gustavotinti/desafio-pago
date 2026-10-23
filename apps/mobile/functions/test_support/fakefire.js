// Firestore em memória + mocks de firebase-functions/firebase-admin/mercadopago
// para exercitar o index.js REAL. Regras imitadas do Firestore que importam:
//  - update() em doc inexistente FALHA (NOT_FOUND) e aborta a transação/batch
//  - transação: leitura depois de escrita é proibida (lança)
//  - escritas da transação/batch são atômicas (aplicadas só no commit)
"use strict";
const Module = require("module");

const store = new Map(); // path -> data
const audit = {authDeleted: [], messages: []};
let readAfterWriteViolations = 0;

const clone = (v) => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
const INC = "__inc";
const TS = "__ts";

function applyPatch(base, patch) {
  const out = clone(base) || {};
  for (const [k, v] of Object.entries(patch)) {
    if (v && typeof v === "object" && INC in v) out[k] = (Number(out[k]) || 0) + v[INC];
    else if (v && typeof v === "object" && TS in v) out[k] = new Date().toISOString();
    else out[k] = clone(v);
  }
  return out;
}
function materialize(data) {
  return applyPatch({}, data);
}

class Snap {
  constructor(ref, data) {
    this.ref = ref; this.id = ref.id; this._d = data;
    this.exists = data !== undefined;
    this.updateTime = {t: Date.now()};
  }
  data() {
    return clone(this._d);
  }
  get(f) {
    return this._d ? this._d[f] : undefined;
  }
}

class DocRef {
  constructor(path) {
    this.path = path; this.id = path.split("/").pop();
  }
  collection(name) {
    return new Query(`${this.path}/${name}`);
  }
  async get() {
    return new Snap(this, clone(store.get(this.path)));
  }
  async set(d, opts) {
    const base = opts && opts.merge ? store.get(this.path) : undefined;
    store.set(this.path, base ? applyPatch(base, d) : materialize(d));
  }
  async update(d) {
    if (!store.has(this.path)) throw notFound(this.path);
    store.set(this.path, applyPatch(store.get(this.path), d));
  }
  async delete() {
    store.delete(this.path);
  }
}

function notFound(p) {
  const e = new Error(`5 NOT_FOUND: No document to update: ${p}`);
  e.code = 5;
  return e;
}

class Query {
  constructor(coll, filters = [], order = [], lim = null) {
    this.coll = coll; this.filters = filters; this.order = order; this.lim = lim;
  }
  doc(id) {
    return new DocRef(`${this.coll}/${id || Math.random().toString(36).slice(2, 12)}`);
  }
  async add(d) {
    const r = this.doc(); await r.set(d); return r;
  }
  where(f, op, v) {
    return new Query(this.coll, [...this.filters, [f, op, v]], this.order, this.lim);
  }
  orderBy(f, dir = "asc") {
    return new Query(this.coll, this.filters, [...this.order, [f, dir]], this.lim);
  }
  limit(n) {
    return new Query(this.coll, this.filters, this.order, n);
  }
  _run() {
    let docs = [];
    for (const [p, d] of store) {
      const i = p.lastIndexOf("/");
      if (p.slice(0, i) !== this.coll) continue;
      docs.push(new Snap(new DocRef(p), clone(d)));
    }
    for (const [f, op, v] of this.filters) {
      docs = docs.filter((s) => {
        const x = s._d[f];
        switch (op) {
          case "==": return x === v;
          case "!=": return x !== v;
          case "<=": return x <= v;
          case ">=": return x >= v;
          case "<": return x < v;
          case ">": return x > v;
          case "in": return v.includes(x);
          case "array-contains": return Array.isArray(x) && x.includes(v);
          default: throw new Error("op " + op);
        }
      });
    }
    for (const [f, dir] of [...this.order].reverse()) {
      docs.sort((a, b) => {
        const A = a._d[f]; const B = b._d[f];
        const c = A < B ? -1 : A > B ? 1 : 0;
        return dir === "desc" ? -c : c;
      });
    }
    if (this.lim != null) docs = docs.slice(0, this.lim);
    return {docs, empty: docs.length === 0, size: docs.length,
      forEach: (fn) => docs.forEach(fn)};
  }
  async get() {
    return this._run();
  }
  count() {
    return {get: async () => ({data: () => ({count: this._run().size})})};
  }
  aggregate(spec) {
    return {get: async () => {
      const docs = this._run().docs;
      const out = {};
      for (const [k, v] of Object.entries(spec)) {
        out[k] = docs.reduce((t, d) => t + (Number(d._d[v.__sum]) || 0), 0);
      }
      return {data: () => out};
    }};
  }
}

function makeWriter(strictTx) {
  const ops = [];
  let wrote = false;
  const w = {
    set(ref, d, opts) {
      wrote = true; ops.push(["set", ref, d, opts]); return w;
    },
    update(ref, d) {
      wrote = true; ops.push(["update", ref, d]); return w;
    },
    delete(ref) {
      wrote = true; ops.push(["delete", ref]); return w;
    },
    _checkRead() {
      if (strictTx && wrote) {
        readAfterWriteViolations++;
        throw new Error("Firestore transactions require all reads to be executed before all writes.");
      }
    },
    _commit() {
      // valida tudo antes de aplicar (atomicidade)
      const sim = new Map(store);
      for (const [k, ref, d, opts] of ops) {
        if (k === "update" && !sim.has(ref.path)) throw notFound(ref.path);
        if (k === "set") {
          const base = opts && opts.merge ? sim.get(ref.path) : undefined;
          sim.set(ref.path, base ? applyPatch(base, d) : materialize(d));
        } else if (k === "update") sim.set(ref.path, applyPatch(sim.get(ref.path), d));
        else sim.delete(ref.path);
      }
      store.clear(); for (const [k, v] of sim) store.set(k, v);
    },
  };
  return w;
}

const db = {
  collection: (n) => new Query(n),
  doc: (p) => new DocRef(p),
  async getAll(...refs) {
    return refs.map((r) => new Snap(r, clone(store.get(r.path))));
  },
  batch() {
    const w = makeWriter(false);
    w.commit = async () => w._commit();
    return w;
  },
  async runTransaction(fn) {
    const w = makeWriter(true);
    const tx = Object.assign(w, {
      async get(x) {
        w._checkRead();
        return x instanceof DocRef ? new Snap(x, clone(store.get(x.path))) : x._run();
      },
      async getAll(...refs) {
        w._checkRead();
        return refs.map((r) => new Snap(r, clone(store.get(r.path))));
      },
    });
    const r = await fn(tx);
    w._commit();
    return r;
  },
};

const FieldValue = {
  increment: (n) => ({[INC]: n}),
  serverTimestamp: () => ({[TS]: true}),
  delete: () => ({__del: true}),
  arrayUnion: (...a) => a,
};

class HttpsError extends Error {
  constructor(code, message, details) {
    super(message); this.code = code; this.details = details;
  }
}

// firebase-functions: todo builder devolve o handler "cru".
const chain = () => new Proxy(() => {}, {
  get: (t, k) => {
    if (k === "onCall" || k === "onRequest" || k === "onRun" ||
        k === "onCreate" || k === "onWrite" || k === "onUpdate" ||
        k === "onDelete" || k === "onFinalize") return (h) => h;
    return chain();
  },
  apply: () => chain(),
});
const functionsMock = new Proxy({}, {
  get: (t, k) => {
    if (k === "https") {
      return new Proxy({}, {get: (t2, k2) => (k2 === "HttpsError" ? HttpsError : (h) => h)});
    }
    if (k === "logger") return console;
    if (k === "config") return () => ({});
    return chain();
  },
});

const adminMock = {
  initializeApp: () => {},
  firestore: Object.assign(() => db, {
    FieldValue,
    AggregateField: {sum: (f) => ({__sum: f})},
    Timestamp: {now: () => ({toMillis: () => Date.now()})},
  }),
  auth: () => ({
    deleteUser: async (uid) => audit.authDeleted.push(uid),
    listUsers: async () => ({users: []}),
  }),
  messaging: () => ({send: async (m) => audit.messages.push(m)}),
  storage: () => ({bucket: () => ({})}),
};

let mpStatus = "approved";
class Payment {
  async get() {
    return {status: mpStatus};
  }
  async create() {
    return {id: 1, point_of_interaction: {transaction_data: {qr_code: "x", qr_code_base64: "y"}}};
  }
}
const mpMock = {MercadoPagoConfig: class {}, Payment};

const origLoad = Module._load;
Module._load = function(req, ...rest) {
  if (req === "firebase-functions" || req === "firebase-functions/v1") return functionsMock;
  if (req === "firebase-admin") return adminMock;
  if (req === "mercadopago") return mpMock;
  return origLoad.call(this, req, ...rest);
};

module.exports = {
  store, db, audit, HttpsError,
  setMpStatus: (s) => {
    mpStatus = s;
  },
  violations: () => readAfterWriteViolations,
  put: (p, d) => store.set(p, clone(d)),
  read: (p) => clone(store.get(p)),
  reset: () => {
    store.clear(); audit.authDeleted.length = 0; audit.messages.length = 0;
  },
};
