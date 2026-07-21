#include "SRC/SYS/HWSHUT.H"
#include "SRC/INPUT/TIMER.H"
#include "SRC/INPUT/KEYBOARD.H"
#include "SRC/INPUT/INT00.H"
#include "SRC/INPUT/MOUSE.H"

void hardware_shutdown(void) {
    keyboard_restore_handler();
    mouse_restore_handler();
    timer_restore_default();
    restore_int00_handler();
}
