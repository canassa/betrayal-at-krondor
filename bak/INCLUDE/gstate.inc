; gstate.inc - the engine GameState as a TASM STRUC. Field names match the C
; struct in structs.h - keep the two in lockstep. Storage is _g_gameState (in
; its owning C unit). Reference a field as [reg].GameState.<f>
; or [_g_gameState + GameState.<f>]. Hand-maintained.

ifndef __GAMESTATE_INC__
__GAMESTATE_INC__ equ 1

GameState	struc
nChapter	dw	?
nParty_gold	dd	?
game_time	dd	?
dwLastActionTimeSnapshot	dd	?
bCombatExitRequest	db	?
nWorldLoopExitRequest	db	?
rsvd_10	db	1 dup(?)
nPrevZoneId	db	?
nZoneId	db	?
nPlayerTileX	db	?
nPlayerTileY	db	?
zoneDefaultCameraPos	db	8 dup(?)
rsvd_1d	db	4 dup(?)
wZoneDefaultCameraHeading	dw	?
abTeleportRecord	db	11 dup(?)
nLastSeenStepSpeed	dw	?
nLastSeenGridStride	dw	?
nWorldStepPending	dw	?
nWorldStepTickCount	db	?
world_step_tick	dw	?
lInsetCameraPosZ	dd	?
pParty_names	db	60 dup(?)
party_members	db	570 dup(?)
party_count	db	?
party_roster	db	3 dup(?)
shared_inventory	db	4 dup(?)
ground_pile	db	4 dup(?)
bPartyDirtyFlags	db	?
dwPopup_retry_state	dw	?
aConditionTickAdvance	dw	6 dup(?)
abActorStatusRanks	db	42 dup(?)
aActorStatModifiers	db	672 dup(?)
nEvtArgActor0	dw	?
nEvtArgActor1	dw	?
nEvtArgStat	dw	?
rsvd_59c	db	2 dup(?)
nEvtArgCount	dw	?
nEvtArgAux1	dw	?
nEvtArgItemId	dw	?
nEvtArgDlgResult	dw	?
lEvtArgGoldCost	dd	?
lEvtArgValue	dd	?
lEvtArgAuxValue	dd	?
nTimerEventPoolCount	dw	?
aTimerEventPool	db	160 dup(?)
wPalEventMask	dw	?
nSpellMenuCasterSlot	dw	?
nSpellMenuPreselect	dw	?
nPalFadeDirty	dw	?
nPrevWorldBrightness	dw	?
world_brightness	dw	?
nPalDaynightDelta	dw	?
nPalAreaBrightness	dw	?
nPalBrightnessBoost	dw	?
nPalBlendWeight	dw	?
objfixed_location_cache	db	22 dup(?)
event_bitmap_lo	db	1063 dup(?)
event_bitmap_hi	db	50 dup(?)
GameState	ends

	extrn	_g_gameState:byte
endif
