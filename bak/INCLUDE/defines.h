/**
 * @file  defines.h
 * @brief Combat-actor flag bits and DOS interrupt-vector numbers.
 */
#ifndef BAK_DEFINES_H
#define BAK_DEFINES_H

#define CAF_READY 0x01
#define CAF_DEAD 0x02
#define CAF_DEFEND_CMD 0x04
#define CAF_PARRY 0x08
#define CAF_FLEE 0x10
#define CAF_POISON 0x20
#define CAF_KNOCKBACK 0x40
#define CAF_AI_SUMMON 0x80

/** @brief INT 24h — the DOS critical-error (Abort/Retry/Fail) handler vector. */
#define INT_CRITICAL_ERROR 0x24
/** @brief INT 67h — the EMS (expanded-memory) driver entry vector. */
#define INT_EMS 0x67

#endif
