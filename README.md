# agent-runtime-protocol

Lispy **CLOS** agent runtime API for [cl-stack](https://github.com/egao1980/cl-stack) — long-lived, suspendable, network-fenced tasks.

This is the execution plane **above** [`compute-protocol`](https://github.com/egao1980/compute-protocol). One-shot `run-sandboxed` stays there. This protocol owns task lifecycle, workspaces, egress policy, and secret refs. Network and `secret-ref` types are defined here so the repo is self-contained (no `compute-protocol` dependency).

| System | Role | Repo |
|--------|------|------|
| `agent-runtime-protocol` (`stack-runtime`) | Protocol / API + in-memory backend | this repo |

Phases: `:pending` `:running` `:suspended` `:failed` `:terminating`.

Conditions (AX-shaped, local-valid): `:workspace-ready`, `:gateway-ready`, `:ready`. Suspend clears Ready with reason `:task-suspended`.

`secret-ref` has `name` / `key` / `inject` (`:env` or `:file`) — no material slot.

```lisp
(asdf:load-system "agent-runtime-protocol")

(let* ((backend (stack-runtime:make-memory-runtime-backend))
       (spec (stack-runtime:make-runtime-task-spec
              :name "demo"
              :workspaces (list (stack-runtime:make-runtime-workspace-spec
                                 :name "ws"
                                 :git '((:repo "https://example.com/foo.git"
                                         :branch "main" :name "foo"))))
              :network (stack-runtime:make-runtime-network-policy
                        :egress '(("example.com" 443)))
              :secrets (list (stack-runtime:make-secret-ref
                              :name "vault" :key "token" :inject :env))))
       (status (stack-runtime:apply-task backend spec)))
  (stack-runtime:runtime-status-phase status) ; => :RUNNING
  (stack-runtime:suspend-task backend "demo")
  (stack-runtime:resume-task backend "demo")
  (stack-runtime:delete-task backend "demo"))
```

`apply-task` establishes `use-value`, `abort`, and `retry`. `exec-in-task` is debug-only and signals `runtime-denied` unless the spec sets `:debug t`. Unknown ids signal `runtime-not-found`; illegal transitions signal `runtime-invalid-phase`.

The in-memory backend materializes fake workspace dirs (git entries → empty dirs + marker files) under `uiop:temporary-directory` or an explicit `:root`. Suspend/resume preserve a path→string file map. It does **not** implement AX gRPC, Redis, Kubernetes, or CRIU.

```bash
sbcl --load examples/lifecycle.lisp
```

## License

MIT
