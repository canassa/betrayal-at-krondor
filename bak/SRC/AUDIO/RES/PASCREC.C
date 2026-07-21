#include "SRC/AUDIO/RES/PASCREC.H"

unsigned char far *advance_pascal_record(unsigned char far *record) {
    return record + record[1] + 2;
}
