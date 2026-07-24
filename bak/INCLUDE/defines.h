/**
 * @file  defines.h
 * @brief Combat-actor flag bits, DOS interrupt-vector numbers and INT 24h
 *        return codes.
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

/** @brief INT 21h — the DOS function-request dispatcher (AH selects the service). */
#define INT_DOS 0x21
/** @brief INT 24h — the DOS critical-error (Abort/Retry/Fail) handler vector. */
#define INT_CRITICAL_ERROR 0x24
/** @brief INT 67h — the EMS (expanded-memory) driver entry vector. */
#define INT_EMS 0x67

/** @brief INT 24h return code (in AL): ignore the error and continue. */
#define INT24_IGNORE 0
/** @brief INT 24h return code (in AL): retry the failed DOS operation. */
#define INT24_RETRY 1
/** @brief INT 24h return code (in AL): abort the program. */
#define INT24_ABORT 2
/** @brief INT 24h return code (in AL): fail the DOS call, returning an error. */
#define INT24_FAIL 3

#endif
