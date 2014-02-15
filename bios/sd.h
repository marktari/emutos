/*
 * sd.h - header for SD/MMC card routines
 *
 * Copyright (c) 2013-2014 The EmuTOS development team
 *
 * Authors:
 *  RFB   Roger Burrows
 *
 * This file is distributed under the GPL, version 2 or at your
 * option any later version.  See doc/license.txt for details.
 */
#ifndef _SD_H
#define _SD_H

#include <portab.h>

#ifdef __mcoldfire__

/* driver functions */
void sd_init(void);
LONG sd_ioctl(UWORD drv,UWORD ctrl,void *arg);
LONG sd_rw(WORD rw,LONG sector,WORD count,LONG buf,WORD dev);

#endif /* __mcoldfire__ */

#endif /* _SD_H */
