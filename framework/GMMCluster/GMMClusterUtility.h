/*
* All questions regarding the software should be addressed to
* 
*       Prof. Charles A. Bouman
*       Purdue University
*       School of Electrical and Computer Engineering
*       1285 Electrical Engineering Building
*       West Lafayette, IN 47907-1285
*       USA
*       +1 765 494 0340
*       +1 765 494 3358 (fax)
*       email:  bouman@ecn.purdue.edu
*       http://www.ece.purdue.edu/~bouman
* 
* Copyright (c) 1995 The Board of Trustees of Purdue University.
*
* Permission to use, copy, modify, and distribute this software and its
* documentation for any purpose, without fee, and without written agreement is
* hereby granted, provided that the above copyright notice and the following
* two paragraphs appear in all copies of this software.
*
* IN NO EVENT SHALL PURDUE UNIVERSITY BE LIABLE TO ANY PARTY FOR DIRECT,
* INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE
* USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF PURDUE UNIVERSITY HAS
* BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*
* PURDUE UNIVERSITY SPECIFICALLY DISCLAIMS ANY WARRANTIES, INCLUDING, BUT NOT
* LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
* PARTICULAR PURPOSE.  THE SOFTWARE PROVIDED HEREUNDER IS ON AN "AS IS" BASIS,
* AND PURDUE UNIVERSITY HAS NO OBLIGATION TO PROVIDE MAINTENANCE, SUPPORT,
* UPDATES, ENHANCEMENTS, OR MODIFICATIONS.
*/


#ifndef CLUST_UTIL_H
#define CLUST_UTIL_H

#import <stddef.h>
#import <string.h>

short I_SigSetNClasses(SigSet *S);
ClassData *I_AllocClassData(SigSet *S, ClassSig *C, size_t npixels);
void I_InitSigSet(SigSet *S);
void I_SigSetNBands(SigSet *S, int nbands);
ClassSig *I_NewClassSig(SigSet *S);
SubSig *I_NewSubSig (SigSet *S, ClassSig *C);
void I_SetSigTitle(SigSet *S, char *title);
char *I_GetSigTitle(SigSet *S);
void I_SetClassTitle(ClassSig *C, char *title);
char *I_GetClassTitle(ClassSig *C);
void I_DeallocClassData(ClassSig *C);
void I_DeallocSubSig(ClassSig *C);
void I_DeallocClassSig(SigSet *S);
void I_DeallocSigSet(SigSet *S);


#endif /* CLUST_UTIL_H */

