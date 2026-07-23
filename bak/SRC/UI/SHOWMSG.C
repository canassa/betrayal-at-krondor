#include "structs.h"
#include "SRC/UI/SHOWMSG.H"
#include "SRC/DIALOG/DIALOG.H"

void far show_message_plus_1600000(int msg_id) {
    dialog_play_record((long)msg_id + 1600000, 1);
}
