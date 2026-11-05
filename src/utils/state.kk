module state

pub effect state<a>
    fun get() : a
    fun set(x : a) : ()

pub fun modify(f : a -> <state<a>|e> a) : <state<a>|e> ()
    set(f(get()))

pub fun gets(f : a -> <state<a>|e> b) : <state<a>|e> b
    f(get())

pub fun swap(new : a) : state<a> a
    val old = get()
    set(new)
    old

pub fun update(f : a -> <state<a>|e> a) : <state<a>|e> a
    modify(f)
    get()

pub fun local(action : () -> <state<a>|e> b) : <state<a>|e> b
    val saved = get()
    val r = action()
    set(saved)
    r

pub fun modified(f : a -> <state<a>|e> a, action : () -> <state<a>|e> b) : <state<a>|e> b
    with local
    modify(f)
    action()

fun inc() : state<int> ()
    modify(_+ 1)

pub fun handle-state(initial : a, action : () -> <state<a>|e> b) : e b
    var st := initial
    with handler
        fun get() st
        fun set(s) st := s
    action()

pub fun state(initial : a, action : () -> <state<a>|e> b) : e b
    handle-state(initial, action)

pub fun zoom(
    getter : (a   ) -> <state<a>|e> b,
    setter : (a, b) -> <state<a>|e> a,
    action : (    ) -> <state<b>, state<a>|e> c
) : <state<a>|e> c
    with handler
        fun get() getter(get())
        fun set(x) set(setter(get(), x))
    action()

pub fun run(initial : a, action : () -> <state<a>|e> b) : e (b, a)
    var st := initial
    with handler
        return(x) (x, st)
        fun get() st
        fun set(s) st := s
    action()

pub fun exec(initial, action)
    state/run(initial, action).snd

struct person
    name : string
    age : int

pub fun person/show(pe__derived_show : person)
  "Person("
  ++ "name=" ++ pe__derived_show.name.show ++ ", "
  ++ "age=" ++ pe__derived_show.age.show
  ++ ")"

val timmy = Person("Timmy", 25)

fun zoom-example()
    with zoom(name) fn(p : person, nm) p(name=nm)
    val nm = get()
    set(nm.to-upper)
    "The person is " ++ nm

pub fun fresh() : state<int> int
    val n = get()
    set(n + 1)
    n

pub fun when(
    p : (a) -> <state<a>|e> bool,
    action : () -> <state<a>|e> ()
) : <state<a>|e> ()
    if p(get()) then action()

fun when-example()
    var res := 0
    repeat(100)
        res := fresh()
        when(_ % 3 == 0)
            println("Fizz")
        when(_ % 5 == 0)
            println("Buzz")
    res

pub fun while(p : a -> <div,state<a>|e> bool, action : () -> <div,state<a>|e> ()) : <div,state<a>|e> ()
    while { p(get()) }
        action()
