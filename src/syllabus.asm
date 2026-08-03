;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                 G A M E  B O Y   S Y L L A B U S                 ;;
;;——————————————————————————————————————————————————————————————————;;
;;                      Sebastián Romero Cruz                       ;;
;;                          Aestās MMXXVI                           ;;
;;——————————————————————————————————————————————————————————————————;;
;;                                                                  ;;
;;                        E8 AB B8 E8 A1 8C                         ;;
;;                        E7 84 A1 E5 B8 B8                         ;;
;;                                                                  ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Includes
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
INCLUDE "lib/hardware.inc"
INCLUDE "lib/font.asm"
INCLUDE "lib/comparch-slides.asm"


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Header Housekeeping.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SECTION "Header", ROM0[$100]

	jp EntryPoint

	ds $150 - @, 0 ; Make room for the header

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Initialisation
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
EntryPoint:
	; Shut down audio circuitry
	ld a, 0
	ld [rNR52], a

	; Do not turn the LCD off outside of VBlank
WaitVBlank:
	ld a, [rLY]
	cp 144
	jr c, WaitVBlank

	; Turn the LCD off
	ld a, 0
	ld [rLCDC], a

	; Copy the tile data (shared by every slide)
	ld de, FontTiles
	ld hl, $9000
	ld bc, FontTiles.End - FontTiles
	call Memcpy

	; Initialize display registers
	ld a, %11100100
	ld [rBGP], a

	; Initialize input/slide state
	ld a, 0
	ld [wCurKeys], a
	ld [wNewKeys], a
	ld [wCurSlide], a

	; Enable the VBlank interrupt
	ld a, IE_VBLANK
	ld [rIE], a
	ei ; unmask interrupts globally (IME on), rIE alone can't fire one

	; Load and reveal the first slide — same path every later transition uses
	call LoadSlide


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Main loop: wait for VBlank, poll input, advance/retreat the
;; slide on an edge-triggered A/B press, then loop. The double wait
;; (leave LY >= 144, then re-enter it) guarantees exactly one
;; UpdateKeys call per frame, even if the loop body runs faster
;; than a ful frame.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
Main:
WaitVBlank2:
	halt
	ld a, [wVBlankFlag]
	cp 0
	jr z, WaitVBlank2

	ld a, 0
	ld [wVBlankFlag], a

	call UpdateKeys

	; A pressed? Advance to the next slide, unless already on the last one.
	ld a, [wNewKeys]
	and a, PAD_A
	jp z, CheckB
	ld a, [wCurSlide]
	cp a, NumSlides - 1
	jp z, CheckB
	inc a
	ld [wCurSlide], a
	call LoadSlide
	jp Main

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; B pressed? Go back to the previous slide, unless already on the  ;;
;; first one.														;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
CheckB:
	ld a, [wNewKeys]
	and a, PAD_B
	jp z, Main
	ld a, [wCurSlide]
	cp a, 0
	jp z, Main
	dec a
	ld [wCurSlide], a
	call LoadSlide
	jp Main

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; UpdateKeys: polls the joypad and writes wCurKeys (buttons
;; currently held) and wNewKeys (buttons that just transitioned
;; from up to down this frame). Straight from the gbdev.io Input
;; chapter, this exact double-nibble dance is what the JOYP
;; hardware requires; treat .onenibble as "trust me" for now.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
UpdateKeys:
	; Poll half the controller
	ld a, JOYP_GET_BUTTONS
	call .onenibble
	ld b, a ; B7-4 = 1; B3-0 = unpressed buttons

	; Poll the other half
	ld a, JOYP_GET_CTRL_PAD
	call .onenibble
	swap a ; A7-4 = unpressed directions; A3-0 = 1
	xor a, b ; A = pressed buttons + directions
	ld b, a ; B = pressed buttons + directions

	; And release the controller
	ld a, JOYP_GET_NONE
	ld [rJOYP], a

	; Combine with previous wCurKeys to make wNewKeys
	ld a, [wCurKeys]
	xor a, b ; A = keys that changed state
	and a, b ; A = keys that changed to pressed
	ld [wNewKeys], a
	ld a, b
	ld [wCurKeys], a
	ret

.onenibble
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;; writes the select bits you pass in (JOYP_GET_BUTTONS or
	;; JOYP_GET_CTRL_PAD) into the register. This tells the hardware
	;; which of the two 4-key groups to route onto bits 0-3.
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	ld [rJOYP], a

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;; it exists purely to spend ~10 cycles. This is the SM83/hardware
	;; equivalent of a debounce delay
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	call .knownret

	; the first two are thrown away (still letting the matrix settle further)
	ld a, [rJOYP]
	ld a, [rJOYP]

	ld a, [rJOYP] ; this read counts

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;; forces the upper nibble to all 1s and leaves the lower nibble
	;;(the actual key states) untouched. Since unpressed = 1 and
	;; pressed = 0, this gives you a clean byte: 1111 in the top nibble
	;; (unused/don't-care), and the real pressed/unpressed bits in the
	;; bottom nibble.
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	or a, $F0 ; A7-4 = 1; A3-0 = unpressed keys

.knownret
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;; this returns twice: once from the call .knownret (immediately,
	;; cycle-burning), and once for real at the end when .onenibble
	;; itself returns. Same ret instruction, two different callers.
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; LoadSlide: looks up wCurSlide's tilemap pointer, blanks the BG
;; map (so there's something to "type" onto), then reveals it via
;; RevealCopy.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
LoadSlide:
	ld a, [wCurSlide]
	add a, a
	ld l, a
	ld h, 0
	ld de, Slides
	add hl, de
	ld a, [hl+]
	ld e, a
	ld a, [hl]
	ld d, a ; de = address of the chosen SlideXMap

	ld a, 0
	ld [rLCDC], a ; safe: LoadSlide is only ever called during VBlank

	push de           ; stash the tilemap pointer while we blank
	ld hl, $9800
	ld bc, 32 * 18
.blank
	ld a, SPACE_TILE
	ld [hli], a
	dec bc
	ld a, b
	or a, c
	jr nz, .blank
	pop de

	ld a, LCDC_ON | LCDC_BG_ON
	ld [rLCDC], a

	ld hl, $9800
	ld bc, 32 * 18
	call RevealCopy
	ret

; Copies bc bytes from [de] to [hl], one byte at a time.
Memcpy:
	ld a, [de]
	ld [hli], a
	inc de
	dec bc
	ld a, b
	or a, c
	jr nz, Memcpy
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; RevealCopy: identical to Memcpy, except it waits for a fresh
;; VBlank before each byte. One tile revealed per frame i.e the
;; "typewriter" effect. Blocks until the whole map is copied.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
RevealCopy:
.wait
	halt
	ld a, [wVBlankFlag]
	cp 0
	jr z, .wait

	ld a, 0
	ld [wVBlankFlag], a

	ld a, [de]
	ld [hli], a
	inc de
	dec bc
	ld a, b
	or a, c
	jr nz, RevealCopy
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Interrupt Handler: fires automatically whenever LY reaches 144,
;; i.e. once per frame, the moment VBlank begins. This is the whole
;; VBlank-interrupt model in one place:
;;
;;   1. EntryPoint sets IE_VBLANK in rIE (this source may interrupt)
;;      and then executes ei (interrupts are unmasked globally).
;;   2. From then on, the hardware jumps here on its own the instant
;;      LY hits 144, regardless of what the CPU was doing.
;;   3. This handler does the bare minimum: save af (it's the only
;;      register touched), set wVBlankFlag so the interrupted code
;;      knows a VBlank happened, restore af, then reti — a normal
;;      ret plus re-enabling IME, which the CPU cleared on entry.
;;   4. Main and RevealCopy each halt (sleep the CPU until any
;;      interrupt fires), then check wVBlankFlag and clear it once
;;      seen. That flag is the only channel between this handler and
;;      the rest of the program; nothing else here talks to them.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SECTION "Interrupt Handler", ROM0[$0040]

	push af

	ld a, %00000001
	ld [wVBlankFlag], a

	pop af

	reti


SECTION "Input Variables", WRAM0

wCurKeys: db    ; key state
wNewKeys: db    ; key strokes
wCurSlide: db   ; current slide pointer
wVBlankFlag: db ;


SECTION "Slide Table", ROM0

Slides:
	dw Slide0Map, Slide1Map, Slide2Map, Slide3Map, Slide4Map, Slide5Map, Slide6Map, Slide7Map, Slide8Map, Slide9Map, Slide10Map, Slide11Map, Slide12Map, Slide13Map, Slide14Map, Slide15Map
.End:

def NumSlides equ (Slides.End - Slides) / 2
def SPACE_TILE equ 8 ; the ' ' glyph in FontTiles — used to blank the BG map before a reveal
