module reader

pub effect reader<a>
    fun ask() : a

pub fun asks(f : a -> <reader<a>|e> b) : <reader<a>|e> b
    f(ask())

pub fun handle-reader(env : a, action : () -> <reader<a>|e> b) : e b
    with fun ask() env
    action()

pub fun reader(env : a, action : () -> <reader<a>|e> b) : e b
    handle-reader(env, action)

pub fun local(f : a -> <reader<a>|e> a, action : () -> <reader<a>|e> b) : <reader<a>|e> b
    val cur = ask()
    with override fun ask() f(cur)
    action()

pub fun focus<outer, inner>(
    get    : outer -> <reader<outer>|e> inner,
    action : () -> <reader<inner>, reader<outer>|e> c
) : <reader<outer>|e> c
    val outer = ask()
    reader(get(outer), action)

struct config
    host : string
    port : int

fun config/show(co__derived_show : config)
  "Config("
  ++ "host=" ++ co__derived_show.host.show ++ ", "
  ++ "port=" ++ co__derived_show.port.show
  ++ ")"

fun focus-port()
    with focus(port)
    val p : int = ask()
    p.println
    p + 1

fun example()
    with reader-by
        Config(host="localhost", port=80085)
    focus-port()

pub fun reader-by(mk : () -> e a, action : () -> <reader<a>|e> b) : e b
    with fun ask() mk()
    action()
