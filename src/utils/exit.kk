module exit

pub effect exit
    final ctl exit(): a

pub fun exiting(action: () -> <exit|e> ()): e ()
    with final ctl exit() ()
    action()
