#include "structs.h"
#include "SRC/COMBAT/STATS/MONSTAT.H"
#include "SRC/SYS/RAND.H"
#include "SRC/IO/RESOURCE.H"
#include "SRC/COMBAT/STATS/CBSTAT.H"

#include <stdlib.h>
#include <string.h>

int monstat_roll_stat_in_range(Combatant *actor, int max_val, int min_val, int stat_index) {
    int result;

    if (max_val == min_val) {
        result = max_val;
    } else {
        result = RNDR(min_val, max_val);
    }
    if (stat_index != -1) {
        actor->stats[stat_index].max = actor->stats[stat_index].base = (char)result;
    }
    return result;
}

void monstat_roll_stats_from_file(Combatant *actor) {
    int max_val;
    int min_val;
    char numbuf[6];
    char filename[13] = "monst";
    char ext[5] = ".dat";
    int creatureType;
    ResFile *file;

    if (actor->inner->creatureType == 0x12 &&
        cbstat_find_intact_equip_cat(actor, 2) != (ItemRecord far *)0) {
        creatureType = 10;
    } else {
        creatureType = actor->inner->creatureType;
    }
    itoa(creatureType, numbuf, 10);
    strcat(filename, numbuf);
    strcat(filename, ext);

    file = res_fopen(filename, "rb");
    if (file == (ResFile *)0)
        return;

    res_fread(&min_val, 2, 1, file);
    res_fread(&max_val, 2, 1, file);
    monstat_roll_stat_in_range(actor, max_val, min_val, 0);
    res_fread(&min_val, 2, 1, file);
    res_fread(&max_val, 2, 1, file);
    monstat_roll_stat_in_range(actor, max_val, min_val, 1);
    res_fread(&min_val, 2, 1, file);
    res_fread(&max_val, 2, 1, file);
    monstat_roll_stat_in_range(actor, max_val, min_val, 2);
    res_fread(&min_val, 2, 1, file);
    res_fread(&max_val, 2, 1, file);
    monstat_roll_stat_in_range(actor, max_val, min_val, 3);
    res_fread(&min_val, 2, 1, file);
    res_fread(&max_val, 2, 1, file);
    monstat_roll_stat_in_range(actor, max_val, min_val, 5);
    res_fread(&min_val, 2, 1, file);
    res_fread(&max_val, 2, 1, file);
    monstat_roll_stat_in_range(actor, max_val, min_val, 6);
    res_fread(&min_val, 2, 1, file);
    res_fread(&max_val, 2, 1, file);
    monstat_roll_stat_in_range(actor, max_val, min_val, 7);
    res_fread(&min_val, 2, 1, file);
    res_fread(&max_val, 2, 1, file);
    monstat_roll_stat_in_range(actor, max_val, min_val, 4);

    res_fread(&min_val, 2, 1, file);
    res_fread(&max_val, 2, 1, file);
    actor->inner->aiTurnProfile = (unsigned char)monstat_roll_stat_in_range(actor, max_val, min_val, -1);
    res_fread(&min_val, 2, 1, file);
    res_fread(&max_val, 2, 1, file);
    actor->inner->aiEncounterProfile = (unsigned char)monstat_roll_stat_in_range(actor, max_val, min_val, -1);
    res_fread(&min_val, 2, 1, file);
    res_fread(&max_val, 2, 1, file);
    actor->inner->aiPathProfile = (unsigned char)monstat_roll_stat_in_range(actor, max_val, min_val, -1);

    res_fread(&min_val, 2, 1, file);
    res_fread(&max_val, 2, 1, file);
    if (actor->inner->morale != '\0') {
        actor->inner->morale = (unsigned char)monstat_roll_stat_in_range(actor, max_val, min_val, -1);
    }
    res_fclose(file);
}
