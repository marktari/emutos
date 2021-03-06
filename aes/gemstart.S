/*      GEMSTART.S */

/*
*       Copyright 1999, Caldera Thin Clients, Inc.
*                 2002-2017 The EmuTOS development team
*
*       This software is licenced under the GNU Public License.
*       Please see LICENSE.TXT for further information.
*
*                  Historical Copyright
*       -------------------------------------------------------------
*       GEM Application Environment Services              Version 3.0
*       Serial No.  XXXX-0000-654321              All Rights Reserved
*       Copyright (C) 1987                      Digital Research Inc.
*       -------------------------------------------------------------
*/

#include "asmdefs.h"
#include "asmstruct.h"

        .globl  _ui_start
        .globl  _accdesk_start
        .globl  _gemdos
        .globl  _dos_exec

        .extern _ad_stail
        .extern _ad_envrn
        .extern _size_theglo
        .extern _D
        .extern _bzero
        .extern _justretf
        .extern _drwaddr
        .extern _tikcod
        .extern _tikaddr
        .extern _init_p0_stkptr
        .extern _gem_main
        .extern _gl_changerez
        .extern _run_accs_and_desktop
        .extern _disable_interrupts
        .extern _rlr
        .extern _enable_interrupts

        .text

//////////////////////////////////////////////////////////////////////////////
// AES start-up code
//////////////////////////////////////////////////////////////////////////////
_ui_start:
        // obtain our basepage address
        movea.l sp,a5
        movea.l 4(a5),a5

        // set our temporary user stack (needed to call Super ?)
        movea.l #gemusp,sp

        // ad_stail is the address to the cmdline buffer in our basepage
        move.l  a5,d0
        add.l   #0x80,d0
        move.l  d0,_ad_stail

        // mshrink to the needed size for TEXT+DATA+BSS plus 256 bytes.
        move.l  0xC(a5),d0
        add.l   0x14(a5),d0
        add.l   0x1C(a5),d0
        add.l   #0x100,d0
        move.l  d0,-(sp)
        move.l  a5,-(sp)
        clr.w   -(sp)
        move.w  #0x4A,-(sp)
        trap    #1
        lea     12(sp),sp

        // old_gem_ssp = super(0)
        clr.l  -(sp)
        move.w  #0x20,-(sp)
        trap    #1                      // Switch to supervisor mode
        addq.l  #6,sp
        move.l  d0,old_gem_ssp

        // ad_envrn = the pointer to the environ string
#ifdef __mcoldfire__
        lea     save_ad_envrn,a0
        move.l  0x2C(a5),(a0)
#else
        move.l  0x2C(a5),save_ad_envrn
#endif

aes_restart:
        // set our temporary user stack again, so we can call bzero()
        // after an AES restart
        movea.l #gemusp,sp

        // restore original environment pointer
#ifdef __mcoldfire__
        move.l  save_ad_envrn,d0
        move.l  d0,_ad_envrn
#else
        move.l  save_ad_envrn,_ad_envrn
#endif

        // clear the 'global memory' zone whose size is determined by
        // routine size_theglo :-)
        jsr     _size_theglo
        move.l  d0,-(sp)        // size in bytes
        movea.l #_D,a0
        move.l  a0,-(sp)        // address
        jsr     _bzero          // clear it
        addq.l  #8,sp

        // _drwaddr ??? set to just_rts
        lea     _justretf,a0
        move.l  a0,_drwaddr

        // _tikaddr ??? set to tikcod
        lea     _tikcod,a0
        move.l  a0,_tikaddr

        // call C routine to init the SSP in the UDA & return its offset
        jsr     _init_p0_stkptr
        movea.l #_D,a6
        adda.l  d0,a6
        movea.l a6,sp

        // go in C
        jsr     _gem_main

        // Check for resolution change - if so start over again
        move.w  _gl_changerez,d0
        tst.w   d0
        jne     aes_restart

        // Super() to go back to user mode
        move.l  old_gem_ssp,-(sp)
        move.w  #0x20,-(sp)
        trap    #1
        addq.l  #6,sp

        // Pterm0()
        clr.w   -(sp)
        trap    #1


//////////////////////////////////////////////////////////////////////////////
// Run accessories and desktop
//////////////////////////////////////////////////////////////////////////////
_accdesk_start:
        move.l  4(sp),a5                // a5 -> basepage
        movea.l #_D,a0
        move.l  UDA_SPSUPER(a0),sp      // use AES process 0 stack
        move.l  12(a5),d0               // calc memory required
        add.l   20(a5),d0
        add.l   28(a5),d0
        addi.l  #256,d0
        move.l  d0,-(sp)                // Mshrink()
        move.l  a5,-(sp)
        clr.w   -(sp)
        move.w  #0x4a,-(sp)
        trap    #1
        lea     12(sp),sp

        // switch to supervisor mode
        clr.l  -(sp)
        move.w  #0x20,-(sp)
        trap    #1
        addq.l  #6,sp

        jsr     _run_accs_and_desktop

        clr.w   -(sp)                   // Pterm0()
        trap    #1


//////////////////////////////////////////////////////////////////////////////
// Execute a GEMDOS call (see gemdos.c).
//////////////////////////////////////////////////////////////////////////////
_gemdos:
        move.l  (SP)+,saveretaddr
#ifdef __mcoldfire__
        move.l  d2,saveregs
        move.l  a2,saveregs+4
#else
        movem.l d2/a2,saveregs
#endif

        trap    #1
#ifdef __mcoldfire__
        move.l  saveregs,d2
        move.l  saveregs+4,a2
#else
        movem.l saveregs,d2/a2
#endif
        move.l  saveretaddr,-(SP)
        rts


//////////////////////////////////////////////////////////////////////////////
// A wrapper around Pexec. We can't use the above function _gemdos for this
// since _gemdos is not reentrant.
//////////////////////////////////////////////////////////////////////////////
_dos_exec:
        move.l  sp,d1
#ifdef __mcoldfire__
        move.l  a2,-(sp)                // Save registers
        move.l  d2,-(sp)
#else
        movem.l d2/a2,-(sp)             // Save registers
#endif

        // *** WARNING ***
        // We are here on the private supervisor stack of the AES process 0.
        // We are going to call Pexec() from the supervisor mode.
        // The GEMDOS will backup some data on our stack, then it will
        // switch to its private supervisor stack. Then it will switch
        // to the child program (desktop or other) which will call the AES
        // through a trap #2.
        // The AES trap prologue always switch to rlr->p_uda->u_spsuper.
        // That variable currently points to somewhere on our stack.
        // Thus, if we don't take care, the stack pointer may go up in
        // the next trap #2 and cause data corruption.
        // In other words, there is a reentrency problem. The AES context
        // will not be switched when entering the child program, so this
        // AES process will reenter itself. The workaround is to set
        // rlr->p_uda->u_spsuper to a value low enough on the current stack
        // to avoid a stack smashing. We have to estimate the amount of
        // data that will be stored on the stack between here and the next
        // stack switch in trap #2.
        // From the rlr->p_uda->u_spsuper backup below to the next trap #2
        // stack switch, the following data will be pushed on the stack:
        //   - the Pexec() arguments (16 bytes)
        //   - the trap #1 stack frame (0 byte, popped by trap #1 prologue)
        //   - the backup of registers in the trap #1 prologue (50 bytes)
        // Currently, this sums to 66 bytes. The stack has to be adjusted
        // by this value, or more.
        // You must keep an eye on the trap #1 prologue for GEMDOS,
        // when entering in supervisor mode and calling a function
        // other than 0x20. It is located in bdos/rwa.S, label "systk".
        // If some additional data is pushed on the stack before
        // the stack switch, you must add the equivalent room here.

        jsr     _disable_interrupts
        movea.l _rlr,a0
        movea.l PD_UDA(a0),a0
        move.l  UDA_SPSUPER(a0),-(sp)   // Save rlr->p_uda->u_spsuper
        movea.l sp,a1
        suba.l  #0x50,a1                // Adjust the stack (see above)
        move.l  a1,UDA_SPSUPER(a0)
        jsr     _enable_interrupts

        movea.l d1,a1
        move.l  14(a1),-(sp)            // Push parameters on the stack again...
        move.l  10(a1),-(sp)
        move.l  6(a1),-(sp)
        move.w  4(a1),-(sp)
        move.w  #0x4B,-(sp)
        trap    #1                      // ... and execute the Pexec call!
        lea     16(sp),sp

        jsr     _disable_interrupts
        movea.l _rlr,a0
        movea.l PD_UDA(a0),a0
        move.l  (sp)+,UDA_SPSUPER(a0)   // Restore rlr->p_uda->u_spsuper
        jsr     _enable_interrupts

#ifdef __mcoldfire__
        move.l  (sp)+,d2
        move.l  (sp)+,a2
#else
        movem.l (sp)+,d2/a2
#endif
        rts

.bss


old_gem_ssp:
        .ds.l   1



saveretaddr:
        .ds.l   1


// Space for the user stack:
        .ds.b   256
gemusp:


saveregs:
        .ds.l   2

// pointer to original environment, restored on AES restart
save_ad_envrn:
        .ds.l   1
