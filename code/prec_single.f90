! Copyright 2011 Max-Planck-Institut für Eisenforschung GmbH
!
! This file is part of DAMASK,
! the Düsseldorf Advanced MAterial Simulation Kit.
!
! DAMASK is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! DAMASK is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with DAMASK. If not, see <http://www.gnu.org/licenses/>.
!
!##############################################################
!* $Id$
!##############################################################
module prec
!##############################################################

 implicit none
 private
!    *** Precision of real and integer variables ***
 integer,     parameter, public :: pReal = selected_real_kind(6,37)       ! 6 significant digits, up to 1e+-37
 integer,     parameter, public :: pInt  = selected_int_kind(9)           ! up to +- 1e9
 integer,     parameter, public :: pLongInt  = 4                          ! should be 64bit
 real(pReal), parameter, public :: tol_math_check = 1.0e-5_pReal
 real(pReal), parameter, public :: tol_gravityNodePos = 1.0e-36_pReal

! NaN is precision dependent 
! from http://www.hpc.unimelb.edu.au/doc/f90lrm/dfum_035.html
! copy can be found in documentation/Code/Fortran
#ifdef __INTEL_COMPILER
#if __INTEL_COMPILER<1200
 real(pReal), parameter, public :: DAMASK_NaN = Z'Z'7F800001', pReal'
#else
 real(pReal), parameter, public :: DAMASK_NaN = real(Z'7F800001', pReal)
#endif
#else
 real(pReal), parameter, public :: DAMASK_NaN = real(Z'7F800001', pReal)
#endif

 type, public :: p_vec
   real(pReal), dimension(:), pointer :: p
 end type p_vec

 public :: prec_init
 
contains

subroutine prec_init
 use, intrinsic :: iso_fortran_env                                          ! to get compiler_version and compiler_options (at least for gfortran 4.6 at the moment)

 implicit none

!$OMP CRITICAL (write2out)
 write(6,*)
 write(6,*) '<<<+-  prec_single init  -+>>>'
 write(6,*) '$Id$'
#include "compilation_info.f90"
 write(6,'(a,i3)')    ' Bytes for pReal:    ',pReal
 write(6,'(a,i3)')    ' Bytes for pInt:     ',pInt
 write(6,'(a,i3)')    ' Bytes for pLongInt: ',pLongInt
 write(6,'(a,e10.3)') ' NaN:         ',DAMASK_NAN
 write(6,'(a,l3)')    ' NaN /= NaN:         ',DAMASK_NaN/=DAMASK_NaN
 if (DAMASK_NaN == DAMASK_NaN) call quit(9000)
 write(6,*)
!$OMP END CRITICAL (write2out)

end subroutine prec_init

end module prec
