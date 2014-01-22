! Copyright 2011-13 Max-Planck-Institut für Eisenforschung GmbH
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
!--------------------------------------------------------------------------------------------------
! $Id$
!--------------------------------------------------------------------------------------------------
!> @author Franz Roters, Max-Planck-Institut für Eisenforschung GmbH
!> @author Philip Eisenlohr, Max-Planck-Institut für Eisenforschung GmbH
!> @brief elasticity, plasticity, internal microstructure state
!--------------------------------------------------------------------------------------------------
module constitutive
 use prec, only: &
   pInt, &
   pReal, &
   p_vec
 
 implicit none
 private
 type(p_vec),   public, dimension(:,:,:), allocatable :: &
   constitutive_state0, &                                                                            !< pointer array to microstructure at start of BVP inc
   constitutive_partionedState0, &                                                                   !< pointer array to microstructure at start of homogenization inc
   constitutive_subState0, &                                                                         !< pointer array to microstructure at start of crystallite inc
   constitutive_state, &                                                                             !< pointer array to current microstructure (end of converged time step)
   constitutive_state_backup, &                                                                      !< pointer array to backed up microstructure (end of converged time step)
   constitutive_dotState, &                                                                          !< pointer array to evolution of current microstructure
   constitutive_deltaState, &                                                                        !< pointer array to incremental change of current microstructure
   constitutive_previousDotState,&                                                                   !< pointer array to previous evolution of current microstructure
   constitutive_previousDotState2,&                                                                  !< pointer array to 2nd previous evolution of current microstructure
   constitutive_dotState_backup, &                                                                   !< pointer array to backed up evolution of current microstructure
   constitutive_RK4dotState, &                                                                       !< pointer array to evolution of microstructure defined by classical Runge-Kutta method
   constitutive_aTolState                                                                            !< pointer array to absolute state tolerance
 type(p_vec),   public, dimension(:,:,:,:), allocatable :: &
   constitutive_RKCK45dotState                                                                       !< pointer array to evolution of microstructure used by Cash-Karp Runge-Kutta method
 integer(pInt), public, dimension(:,:,:), allocatable :: &
   constitutive_sizeDotState, &                                                                      !< size of dotState array
   constitutive_sizeState, &                                                                         !< size of state array per grain
   constitutive_sizePostResults                                                                      !< size of postResults array per grain
 integer(pInt), public :: &
   constitutive_maxSizeDotState, &
   constitutive_maxSizePostResults
 integer(pInt), private :: &
   constitutive_maxSizeState
 
 public :: & 
   constitutive_init, &
   constitutive_homogenizedC, &
   constitutive_microstructure, &
   constitutive_LpAndItsTangent, &
   constitutive_TandItsTangent, &
   constitutive_collectDotState, &
   constitutive_collectDeltaState, &
   constitutive_postResults
 
 private :: &
   constitutive_hooke_TandItsTangent
 
contains


!--------------------------------------------------------------------------------------------------
!> @brief allocates arrays pointing to array of the various constitutive modules
!--------------------------------------------------------------------------------------------------
subroutine constitutive_init
 use, intrinsic :: iso_fortran_env                                                                  ! to get compiler_version and compiler_options (at least for gfortran 4.6 at the moment)
 use debug, only: &
   debug_level, &
   debug_constitutive, &
   debug_levelBasic
 use numerics, only: &
   numerics_integrator
 use IO, only: &
   IO_error, &
   IO_open_file, &
   IO_open_jobFile_stat, &
   IO_write_jobFile, &
   IO_write_jobIntFile, &
   IO_timeStamp
 use mesh, only: &
   mesh_maxNips, &
   mesh_NcpElems, &
   mesh_element, &
   FE_Nips, &
   FE_geomtype
 use material, only: &
   material_phase, &
   material_Nphase, &
   material_localFileExt, &    
   material_configFile, &    
   phase_name, &
   phase_elasticity, &
   phase_plasticity, &
   phase_plasticityInstance, &
   phase_Noutput, &
   homogenization_Ngrains, &
   homogenization_maxNgrains, &
   ELASTICITY_HOOKE_ID, &
   PLASTICITY_NONE_ID, &
   PLASTICITY_J2_ID, &
   PLASTICITY_PHENOPOWERLAW_ID, &
   PLASTICITY_DISLOTWIN_ID, &
   PLASTICITY_TITANMOD_ID, &
   PLASTICITY_NONLOCAL_ID ,&
   ELASTICITY_HOOKE_label, &
   PLASTICITY_NONE_label, &
   PLASTICITY_J2_label, &
   PLASTICITY_PHENOPOWERLAW_label, &
   PLASTICITY_DISLOTWIN_label, &
   PLASTICITY_TITANMOD_label, &
   PLASTICITY_NONLOCAL_label
 use constitutive_none
 use constitutive_j2
 use constitutive_phenopowerlaw
 use constitutive_titanmod
 use constitutive_dislotwin
 use constitutive_nonlocal

 implicit none
 integer(pInt), parameter :: FILEUNIT = 200_pInt
 integer(pInt) :: &
  g, &                                                                                              !< grain number
  i, &                                                                                              !< integration point number
  e, &                                                                                              !< element number
  cMax, &                                                                                           !< maximum number of grains
  iMax, &                                                                                           !< maximum number of integration points
  eMax, &                                                                                           !< maximum number of elements
  p, &
  s, &
  matID,& 
  myNgrains
 integer(pInt), dimension(:,:), pointer :: thisSize
 character(len=64), dimension(:,:), pointer :: thisOutput
 character(len=32) :: outputName                                                                    !< name of output, intermediate fix until HDF5 output is ready
 logical :: knownPlasticity, nonlocalConstitutionPresent

 nonlocalConstitutionPresent = .false.
 
 
!--------------------------------------------------------------------------------------------------
! parse plasticities from config file
 if (.not. IO_open_jobFile_stat(FILEUNIT,material_localFileExt)) &                                  ! no local material configuration present...
   call IO_open_file(FILEUNIT,material_configFile)                                                  ! ... open material.config file
 call constitutive_none_init(FILEUNIT)
 call constitutive_j2_init(FILEUNIT)
 call constitutive_phenopowerlaw_init(FILEUNIT)
 call constitutive_titanmod_init(FILEUNIT)
 call constitutive_dislotwin_init(FILEUNIT)
 call constitutive_nonlocal_init(FILEUNIT)  
 close(FILEUNIT)
 
 write(6,'(/,a)')   ' <<<+-  constitutive init  -+>>>'
 write(6,'(a)')     ' $Id$'
 write(6,'(a15,a)') ' Current time: ',IO_timeStamp()
#include "compilation_info.f90"
 
!--------------------------------------------------------------------------------------------------
! write description file for constitutive phase output
 call IO_write_jobFile(FILEUNIT,'outputConstitutive') 
 do p = 1_pInt,material_Nphase
   i = phase_plasticityInstance(p)                                                                  ! which instance of a plasticity is present phase
   knownPlasticity = .true.                                                                         ! assume valid
   select case(phase_plasticity(p))                                                                 ! split per constititution
     case (PLASTICITY_NONE_ID)
       outputName = PLASTICITY_NONE_label
       thisOutput => NULL()                                                                         ! constitutive_none_output
       thisSize   => NULL()                                                                         ! constitutive_none_sizePostResult
     case (PLASTICITY_J2_ID)
       outputName = PLASTICITY_J2_label
       thisOutput => constitutive_j2_output
       thisSize   => constitutive_j2_sizePostResult
     case (PLASTICITY_PHENOPOWERLAW_ID)
       outputName = PLASTICITY_PHENOPOWERLAW_label
       thisOutput => constitutive_phenopowerlaw_output
       thisSize   => constitutive_phenopowerlaw_sizePostResult
     case (PLASTICITY_DISLOTWIN_ID)
       outputName = PLASTICITY_DISLOTWIN_label
       thisOutput => constitutive_dislotwin_output
       thisSize   => constitutive_dislotwin_sizePostResult
     case (PLASTICITY_TITANMOD_ID)
       outputName = PLASTICITY_TITANMOD_label
       thisOutput => constitutive_titanmod_output
       thisSize   => constitutive_titanmod_sizePostResult
     case (PLASTICITY_NONLOCAL_ID)
       outputName = PLASTICITY_NONLOCAL_label
       thisOutput => constitutive_nonlocal_output
       thisSize   => constitutive_nonlocal_sizePostResult
     case default
       knownPlasticity = .false.
   end select   
   write(FILEUNIT,'(/,a,/)') '['//trim(phase_name(p))//']'
   if (knownPlasticity) then
     write(FILEUNIT,'(a)') '(plasticity)'//char(9)//trim(outputName)
     do e = 1_pInt,phase_Noutput(p)
       write(FILEUNIT,'(a,i4)') trim(thisOutput(e,i))//char(9),thisSize(e,i)
     enddo
   endif
 enddo
 close(FILEUNIT)
 
!--------------------------------------------------------------------------------------------------
! allocation of states
 cMax = homogenization_maxNgrains
 iMax = mesh_maxNips
 eMax = mesh_NcpElems
 
 allocate(constitutive_state0(cMax,iMax,eMax))            
 allocate(constitutive_partionedState0(cMax,iMax,eMax))
 allocate(constitutive_subState0(cMax,iMax,eMax))
 allocate(constitutive_state(cMax,iMax,eMax))
 allocate(constitutive_state_backup(cMax,iMax,eMax))
 allocate(constitutive_dotState(cMax,iMax,eMax))
 allocate(constitutive_deltaState(cMax,iMax,eMax))
 allocate(constitutive_dotState_backup(cMax,iMax,eMax))
 allocate(constitutive_aTolState(cMax,iMax,eMax))
 allocate(constitutive_sizeDotState(cMax,iMax,eMax),    source=0_pInt)
 allocate(constitutive_sizeState(cMax,iMax,eMax),       source=0_pInt)
 allocate(constitutive_sizePostResults(cMax,iMax,eMax), source=0_pInt)
 if (any(numerics_integrator == 1_pInt)) then
   allocate(constitutive_previousDotState(cMax,iMax,eMax))
   allocate(constitutive_previousDotState2(cMax,iMax,eMax))
 endif
 if (any(numerics_integrator == 4_pInt)) then
   allocate(constitutive_RK4dotState(cMax,iMax,eMax)) 
 endif
 if (any(numerics_integrator == 5_pInt)) then
   allocate(constitutive_RKCK45dotState(6,cMax,iMax,eMax))
 endif
 
 do e = 1_pInt,mesh_NcpElems                                                                        ! loop over elements
   myNgrains = homogenization_Ngrains(mesh_element(3,e)) 
   do i = 1_pInt,FE_Nips(FE_geomtype(mesh_element(2,e)))                                            ! loop over IPs
     do g = 1_pInt,myNgrains                                                                        ! loop over grains
       select case(phase_elasticity(material_phase(g,i,e)))                                            
         case default                                                                               ! so far no output for elasticity
       end select
       matID = phase_plasticityInstance(material_phase(g,i,e))
       select case(phase_plasticity(material_phase(g,i,e)))
         case (PLASTICITY_NONE_ID)
           allocate(constitutive_state0(g,i,e)%p(constitutive_none_sizeState(matID)))
           allocate(constitutive_partionedState0(g,i,e)%p(constitutive_none_sizeState(matID)))
           allocate(constitutive_subState0(g,i,e)%p(constitutive_none_sizeState(matID)))
           allocate(constitutive_state(g,i,e)%p(constitutive_none_sizeState(matID)))
           allocate(constitutive_state_backup(g,i,e)%p(constitutive_none_sizeState(matID)))
           allocate(constitutive_aTolState(g,i,e)%p(constitutive_none_sizeState(matID)))
           allocate(constitutive_dotState(g,i,e)%p(constitutive_none_sizeDotState(matID)))
           allocate(constitutive_deltaState(g,i,e)%p(constitutive_none_sizeDotState(matID)))
           allocate(constitutive_dotState_backup(g,i,e)%p(constitutive_none_sizeDotState(matID)))
           if (any(numerics_integrator == 1_pInt)) then
             allocate(constitutive_previousDotState(g,i,e)%p(constitutive_none_sizeDotState(matID)))
             allocate(constitutive_previousDotState2(g,i,e)%p(constitutive_none_sizeDotState(matID)))
           endif
           if (any(numerics_integrator == 4_pInt)) then
             allocate(constitutive_RK4dotState(g,i,e)%p(constitutive_none_sizeDotState(matID))) 
           endif
           if (any(numerics_integrator == 5_pInt)) then
             do s = 1_pInt,6_pInt
               allocate(constitutive_RKCK45dotState(s,g,i,e)%p(constitutive_none_sizeDotState(matID))) 
             enddo
           endif
           constitutive_state0(g,i,e)%p =           0.0_pReal
           constitutive_aTolState(g,i,e)%p =        1.0_pReal
           constitutive_sizeState(g,i,e) =          0_pInt
           constitutive_sizeDotState(g,i,e) =       0_pInt
           constitutive_sizePostResults(g,i,e) =    0_pInt
         case (PLASTICITY_J2_ID)
           allocate(constitutive_state0(g,i,e)%p(constitutive_j2_sizeState(matID)))
           allocate(constitutive_partionedState0(g,i,e)%p(constitutive_j2_sizeState(matID)))
           allocate(constitutive_subState0(g,i,e)%p(constitutive_j2_sizeState(matID)))
           allocate(constitutive_state(g,i,e)%p(constitutive_j2_sizeState(matID)))
           allocate(constitutive_state_backup(g,i,e)%p(constitutive_j2_sizeState(matID)))
           allocate(constitutive_aTolState(g,i,e)%p(constitutive_j2_sizeState(matID)))
           allocate(constitutive_dotState(g,i,e)%p(constitutive_j2_sizeDotState(matID)))
           allocate(constitutive_deltaState(g,i,e)%p(constitutive_j2_sizeDotState(matID)))
           allocate(constitutive_dotState_backup(g,i,e)%p(constitutive_j2_sizeDotState(matID)))
           if (any(numerics_integrator == 1_pInt)) then
             allocate(constitutive_previousDotState(g,i,e)%p(constitutive_j2_sizeDotState(matID)))
             allocate(constitutive_previousDotState2(g,i,e)%p(constitutive_j2_sizeDotState(matID)))
           endif
           if (any(numerics_integrator == 4_pInt)) then
             allocate(constitutive_RK4dotState(g,i,e)%p(constitutive_j2_sizeDotState(matID))) 
           endif
           if (any(numerics_integrator == 5_pInt)) then
             do s = 1_pInt,6_pInt
               allocate(constitutive_RKCK45dotState(s,g,i,e)%p(constitutive_j2_sizeDotState(matID))) 
             enddo
           endif
           constitutive_state0(g,i,e)%p =           constitutive_j2_stateInit(matID)
           constitutive_aTolState(g,i,e)%p =        constitutive_j2_aTolState(matID)
           constitutive_sizeState(g,i,e) =          constitutive_j2_sizeState(matID)
           constitutive_sizeDotState(g,i,e) =       constitutive_j2_sizeDotState(matID)
           constitutive_sizePostResults(g,i,e) =    constitutive_j2_sizePostResults(matID)
         case (PLASTICITY_PHENOPOWERLAW_ID)
           allocate(constitutive_state0(g,i,e)%p(constitutive_phenopowerlaw_sizeState(matID)))
           allocate(constitutive_partionedState0(g,i,e)%p(constitutive_phenopowerlaw_sizeState(matID)))
           allocate(constitutive_subState0(g,i,e)%p(constitutive_phenopowerlaw_sizeState(matID)))
           allocate(constitutive_state(g,i,e)%p(constitutive_phenopowerlaw_sizeState(matID)))
           allocate(constitutive_state_backup(g,i,e)%p(constitutive_phenopowerlaw_sizeState(matID)))
           allocate(constitutive_aTolState(g,i,e)%p(constitutive_phenopowerlaw_sizeState(matID)))
           allocate(constitutive_dotState(g,i,e)%p(constitutive_phenopowerlaw_sizeDotState(matID)))
           allocate(constitutive_deltaState(g,i,e)%p(constitutive_phenopowerlaw_sizeDotState(matID)))
           allocate(constitutive_dotState_backup(g,i,e)%p(constitutive_phenopowerlaw_sizeDotState(matID)))
           if (any(numerics_integrator == 1_pInt)) then
             allocate(constitutive_previousDotState(g,i,e)%p(constitutive_phenopowerlaw_sizeDotState(matID)))
             allocate(constitutive_previousDotState2(g,i,e)%p(constitutive_phenopowerlaw_sizeDotState(matID)))
           endif
           if (any(numerics_integrator == 4_pInt)) then
             allocate(constitutive_RK4dotState(g,i,e)%p(constitutive_phenopowerlaw_sizeDotState(matID))) 
           endif
           if (any(numerics_integrator == 5_pInt)) then
             do s = 1_pInt,6_pInt
               allocate(constitutive_RKCK45dotState(s,g,i,e)%p(constitutive_phenopowerlaw_sizeDotState(matID))) 
             enddo
           endif
           constitutive_state0(g,i,e)%p =           constitutive_phenopowerlaw_stateInit(matID)
           constitutive_aTolState(g,i,e)%p =        constitutive_phenopowerlaw_aTolState(matID)
           constitutive_sizeState(g,i,e) =          constitutive_phenopowerlaw_sizeState(matID)
           constitutive_sizeDotState(g,i,e) =       constitutive_phenopowerlaw_sizeDotState(matID)
           constitutive_sizePostResults(g,i,e) =    constitutive_phenopowerlaw_sizePostResults(matID)
         case (PLASTICITY_DISLOTWIN_ID)
           allocate(constitutive_state0(g,i,e)%p(constitutive_dislotwin_sizeState(matID)))
           allocate(constitutive_partionedState0(g,i,e)%p(constitutive_dislotwin_sizeState(matID)))
           allocate(constitutive_subState0(g,i,e)%p(constitutive_dislotwin_sizeState(matID)))
           allocate(constitutive_state(g,i,e)%p(constitutive_dislotwin_sizeState(matID)))
           allocate(constitutive_state_backup(g,i,e)%p(constitutive_dislotwin_sizeState(matID)))
           allocate(constitutive_aTolState(g,i,e)%p(constitutive_dislotwin_sizeState(matID)))
           allocate(constitutive_dotState(g,i,e)%p(constitutive_dislotwin_sizeDotState(matID)))
           allocate(constitutive_deltaState(g,i,e)%p(constitutive_dislotwin_sizeDotState(matID)))
           allocate(constitutive_dotState_backup(g,i,e)%p(constitutive_dislotwin_sizeDotState(matID)))
           if (any(numerics_integrator == 1_pInt)) then
             allocate(constitutive_previousDotState(g,i,e)%p(constitutive_dislotwin_sizeDotState(matID)))
             allocate(constitutive_previousDotState2(g,i,e)%p(constitutive_dislotwin_sizeDotState(matID)))
           endif
           if (any(numerics_integrator == 4_pInt)) then
             allocate(constitutive_RK4dotState(g,i,e)%p(constitutive_dislotwin_sizeDotState(matID))) 
           endif
           if (any(numerics_integrator == 5_pInt)) then
             do s = 1_pInt,6_pInt
               allocate(constitutive_RKCK45dotState(s,g,i,e)%p(constitutive_dislotwin_sizeDotState(matID))) 
             enddo
           endif
           constitutive_state0(g,i,e)%p =           constitutive_dislotwin_stateInit(matID)
           constitutive_aTolState(g,i,e)%p =        constitutive_dislotwin_aTolState(matID)
           constitutive_sizeState(g,i,e) =          constitutive_dislotwin_sizeState(matID)
           constitutive_sizeDotState(g,i,e) =       constitutive_dislotwin_sizeDotState(matID)
           constitutive_sizePostResults(g,i,e) =    constitutive_dislotwin_sizePostResults(matID)
         case (PLASTICITY_TITANMOD_ID)
           allocate(constitutive_state0(g,i,e)%p(constitutive_titanmod_sizeState(matID)))
           allocate(constitutive_partionedState0(g,i,e)%p(constitutive_titanmod_sizeState(matID)))
           allocate(constitutive_subState0(g,i,e)%p(constitutive_titanmod_sizeState(matID)))
           allocate(constitutive_state(g,i,e)%p(constitutive_titanmod_sizeState(matID)))
           allocate(constitutive_state_backup(g,i,e)%p(constitutive_titanmod_sizeState(matID)))
           allocate(constitutive_aTolState(g,i,e)%p(constitutive_titanmod_sizeState(matID)))
           allocate(constitutive_dotState(g,i,e)%p(constitutive_titanmod_sizeDotState(matID)))
           allocate(constitutive_deltaState(g,i,e)%p(constitutive_titanmod_sizeDotState(matID)))
           allocate(constitutive_dotState_backup(g,i,e)%p(constitutive_titanmod_sizeDotState(matID)))
           if (any(numerics_integrator == 1_pInt)) then
             allocate(constitutive_previousDotState(g,i,e)%p(constitutive_titanmod_sizeDotState(matID)))
             allocate(constitutive_previousDotState2(g,i,e)%p(constitutive_titanmod_sizeDotState(matID)))
           endif
           if (any(numerics_integrator == 4_pInt)) then
             allocate(constitutive_RK4dotState(g,i,e)%p(constitutive_titanmod_sizeDotState(matID))) 
           endif
           if (any(numerics_integrator == 5_pInt)) then
             do s = 1_pInt,6_pInt
               allocate(constitutive_RKCK45dotState(s,g,i,e)%p(constitutive_titanmod_sizeDotState(matID))) 
             enddo
           endif
           constitutive_state0(g,i,e)%p =           constitutive_titanmod_stateInit(matID)
           constitutive_aTolState(g,i,e)%p =        constitutive_titanmod_aTolState(matID)
           constitutive_sizeState(g,i,e) =          constitutive_titanmod_sizeState(matID)
           constitutive_sizeDotState(g,i,e) =       constitutive_titanmod_sizeDotState(matID)
           constitutive_sizePostResults(g,i,e) =    constitutive_titanmod_sizePostResults(matID)
         case (PLASTICITY_NONLOCAL_ID)
           nonlocalConstitutionPresent = .true.
           if(myNgrains/=1_pInt) call IO_error(252_pInt, e,i,g)
           allocate(constitutive_state0(g,i,e)%p(constitutive_nonlocal_sizeState(matID)))
           allocate(constitutive_partionedState0(g,i,e)%p(constitutive_nonlocal_sizeState(matID)))
           allocate(constitutive_subState0(g,i,e)%p(constitutive_nonlocal_sizeState(matID)))
           allocate(constitutive_state(g,i,e)%p(constitutive_nonlocal_sizeState(matID)))
           allocate(constitutive_state_backup(g,i,e)%p(constitutive_nonlocal_sizeState(matID)))
           allocate(constitutive_aTolState(g,i,e)%p(constitutive_nonlocal_sizeState(matID)))
           allocate(constitutive_dotState(g,i,e)%p(constitutive_nonlocal_sizeDotState(matID)))
           allocate(constitutive_deltaState(g,i,e)%p(constitutive_nonlocal_sizeDotState(matID)))
           allocate(constitutive_dotState_backup(g,i,e)%p(constitutive_nonlocal_sizeDotState(matID)))
           if (any(numerics_integrator == 1_pInt)) then
             allocate(constitutive_previousDotState(g,i,e)%p(constitutive_nonlocal_sizeDotState(matID)))
             allocate(constitutive_previousDotState2(g,i,e)%p(constitutive_nonlocal_sizeDotState(matID)))
           endif
           if (any(numerics_integrator == 4_pInt)) then
             allocate(constitutive_RK4dotState(g,i,e)%p(constitutive_nonlocal_sizeDotState(matID))) 
           endif
           if (any(numerics_integrator == 5_pInt)) then
             do s = 1_pInt,6_pInt
               allocate(constitutive_RKCK45dotState(s,g,i,e)%p(constitutive_nonlocal_sizeDotState(matID))) 
             enddo
           endif
           constitutive_aTolState(g,i,e)%p =        constitutive_nonlocal_aTolState(matID)
           constitutive_sizeState(g,i,e) =          constitutive_nonlocal_sizeState(matID)
           constitutive_sizeDotState(g,i,e) =       constitutive_nonlocal_sizeDotState(matID)
           constitutive_sizePostResults(g,i,e) =    constitutive_nonlocal_sizePostResults(matID)
       end select
     enddo
   enddo
 enddo
 if (nonlocalConstitutionPresent) &
   call constitutive_nonlocal_stateInit(constitutive_state0(1,1:iMax,1:eMax))
 do e = 1_pInt,mesh_NcpElems                                                                        ! loop over elements
   myNgrains = homogenization_Ngrains(mesh_element(3,e)) 
   forall(i = 1_pInt:FE_Nips(FE_geomtype(mesh_element(2,e))), g = 1_pInt:myNgrains)
     constitutive_partionedState0(g,i,e)%p = constitutive_state0(g,i,e)%p
     constitutive_state(g,i,e)%p = constitutive_state0(g,i,e)%p                                     ! need to be defined for first call of constitutive_microstructure in crystallite_init
   endforall
 enddo
 
!--------------------------------------------------------------------------------------------------
! write out state size file
 call IO_write_jobIntFile(777,'sizeStateConst', size(constitutive_sizeState))
 write (777,rec=1) constitutive_sizeState
 close(777)

!--------------------------------------------------------------------------------------------------
! report
 constitutive_maxSizeState       = maxval(constitutive_sizeState)
 constitutive_maxSizeDotState    = maxval(constitutive_sizeDotState)
 constitutive_maxSizePostResults = maxval(constitutive_sizePostResults)
 
 if (iand(debug_level(debug_constitutive),debug_levelBasic) /= 0_pInt) then
   write(6,'(a32,1x,7(i8,1x))')   'constitutive_state0:          ', shape(constitutive_state0)
   write(6,'(a32,1x,7(i8,1x))')   'constitutive_partionedState0: ', shape(constitutive_partionedState0)
   write(6,'(a32,1x,7(i8,1x))')   'constitutive_subState0:       ', shape(constitutive_subState0)
   write(6,'(a32,1x,7(i8,1x))')   'constitutive_state:           ', shape(constitutive_state)
   write(6,'(a32,1x,7(i8,1x))')   'constitutive_aTolState:       ', shape(constitutive_aTolState)
   write(6,'(a32,1x,7(i8,1x))')   'constitutive_dotState:        ', shape(constitutive_dotState)
   write(6,'(a32,1x,7(i8,1x))')   'constitutive_deltaState:      ', shape(constitutive_deltaState)
   write(6,'(a32,1x,7(i8,1x))')   'constitutive_sizeState:       ', shape(constitutive_sizeState)
   write(6,'(a32,1x,7(i8,1x))')   'constitutive_sizeDotState:    ', shape(constitutive_sizeDotState)
   write(6,'(a32,1x,7(i8,1x),/)') 'constitutive_sizePostResults: ', shape(constitutive_sizePostResults)
   write(6,'(a32,1x,7(i8,1x))')   'maxSizeState:       ', constitutive_maxSizeState
   write(6,'(a32,1x,7(i8,1x))')   'maxSizeDotState:    ', constitutive_maxSizeDotState
   write(6,'(a32,1x,7(i8,1x))')   'maxSizePostResults: ', constitutive_maxSizePostResults
 endif
 flush(6)
 
end subroutine constitutive_init


!--------------------------------------------------------------------------------------------------
!> @brief returns the homogenize elasticity matrix
!--------------------------------------------------------------------------------------------------
pure function constitutive_homogenizedC(ipc,ip,el)
 use material, only: &
   phase_plasticity, &
   material_phase, &
   PLASTICITY_NONE_ID, &
   PLASTICITY_J2_ID, &
   PLASTICITY_PHENOPOWERLAW_ID, &
   PLASTICITY_DISLOTWIN_ID, &
   PLASTICITY_TITANMOD_ID, &
   PLASTICITY_NONLOCAL_ID
 use constitutive_none, only: &
   constitutive_none_homogenizedC
 use constitutive_j2, only: &
   constitutive_j2_homogenizedC
 use constitutive_phenopowerlaw, only: &
   constitutive_phenopowerlaw_homogenizedC
 use constitutive_dislotwin, only: &
   constitutive_dislotwin_homogenizedC
 use constitutive_titanmod, only: &
   constitutive_titanmod_homogenizedC
 use constitutive_nonlocal, only: &
   constitutive_nonlocal_homogenizedC
 
 implicit none
 real(pReal), dimension(6,6) :: constitutive_homogenizedC
 integer(pInt), intent(in) :: &
   ipc, &                                                                                            !< grain number
   ip, &                                                                                             !< integration point number
   el                                                                                                !< element number

 select case (phase_plasticity(material_phase(ipc,ip,el)))
 
   case (PLASTICITY_NONE_ID)
     constitutive_homogenizedC = constitutive_none_homogenizedC(ipc,ip,el)
     
   case (PLASTICITY_J2_ID)
     constitutive_homogenizedC = constitutive_j2_homogenizedC(ipc,ip,el)
     
   case (PLASTICITY_PHENOPOWERLAW_ID)
     constitutive_homogenizedC = constitutive_phenopowerlaw_homogenizedC(ipc,ip,el)

   case (PLASTICITY_DISLOTWIN_ID)
     constitutive_homogenizedC = constitutive_dislotwin_homogenizedC(constitutive_state,ipc,ip,el) 
    
   case (PLASTICITY_TITANMOD_ID)
     constitutive_homogenizedC = constitutive_titanmod_homogenizedC(constitutive_state,ipc,ip,el)
 
   case (PLASTICITY_NONLOCAL_ID)
     constitutive_homogenizedC = constitutive_nonlocal_homogenizedC(ipc,ip,el)
     
 end select

end function constitutive_homogenizedC


!--------------------------------------------------------------------------------------------------
!> @brief calls microstructure function of the different constitutive models
!--------------------------------------------------------------------------------------------------
subroutine constitutive_microstructure(temperature, Fe, Fp, ipc, ip, el)
 use material, only: &
   phase_plasticity, &
   material_phase, &
   PLASTICITY_DISLOTWIN_ID, &
   PLASTICITY_TITANMOD_ID, &
   PLASTICITY_NONLOCAL_ID
 use constitutive_titanmod, only: &
   constitutive_titanmod_microstructure
 use constitutive_dislotwin, only: &
   constitutive_dislotwin_microstructure
 use constitutive_nonlocal, only: &
   constitutive_nonlocal_microstructure
 
 implicit none
 integer(pInt), intent(in) :: &
   ipc, &                                                                                           !< grain number
   ip, &                                                                                            !< integration point number
   el                                                                                               !< element number
 real(pReal),   intent(in) :: &
   temperature
 real(pReal),   intent(in), dimension(3,3) :: &
   Fe, &                                                                                            !< elastic deformation gradient
   Fp                                                                                               !< plastic deformation gradient
 
 select case (phase_plasticity(material_phase(ipc,ip,el)))
       
   case (PLASTICITY_DISLOTWIN_ID)
     call constitutive_dislotwin_microstructure(temperature,constitutive_state,ipc,ip,el)

   case (PLASTICITY_TITANMOD_ID)
     call constitutive_titanmod_microstructure(temperature,constitutive_state,ipc,ip,el)

   case (PLASTICITY_NONLOCAL_ID)
     call constitutive_nonlocal_microstructure(constitutive_state,Fe,Fp,ipc,ip,el)

 end select
 
end subroutine constitutive_microstructure


!--------------------------------------------------------------------------------------------------
!> @brief  contains the constitutive equation for calculating the velocity gradient  
!--------------------------------------------------------------------------------------------------
subroutine constitutive_LpAndItsTangent(Lp, dLp_dTstar, Tstar_v, temperature, ipc, ip, el)
 use math, only: &
   math_identity2nd
 use material, only: &
   phase_plasticity, &
   material_phase, &
   PLASTICITY_NONE_ID, &
   PLASTICITY_J2_ID, &
   PLASTICITY_PHENOPOWERLAW_ID, &
   PLASTICITY_DISLOTWIN_ID, &
   PLASTICITY_TITANMOD_ID, &
   PLASTICITY_NONLOCAL_ID
 use constitutive_j2, only: &
   constitutive_j2_LpAndItsTangent
 use constitutive_phenopowerlaw, only: &
   constitutive_phenopowerlaw_LpAndItsTangent 
 use constitutive_dislotwin, only: &
   constitutive_dislotwin_LpAndItsTangent
 use constitutive_titanmod, only: &
   constitutive_titanmod_LpAndItsTangent
 use constitutive_nonlocal, only: &
   constitutive_nonlocal_LpAndItsTangent
 
 implicit none
 integer(pInt), intent(in) :: &
   ipc, &                                                                                           !< grain number
   ip, &                                                                                            !< integration point number
   el                                                                                               !< element number
 real(pReal),   intent(in) :: &
   Temperature
 real(pReal),   intent(in),  dimension(6) :: &
   Tstar_v                                                                                          !< 2nd Piola-Kirchhoff stress
 real(pReal),   intent(out), dimension(3,3) :: &
   Lp                                                                                               !< plastic velocity gradient
 real(pReal),   intent(out), dimension(9,9) :: &
   dLp_dTstar                                                                                       !< derivative of Lp with respect to Tstar (4th-order tensor)
 
 select case (phase_plasticity(material_phase(ipc,ip,el)))
 
   case (PLASTICITY_NONE_ID)
     Lp = 0.0_pReal
     dLp_dTstar = math_identity2nd(9)
    
   case (PLASTICITY_J2_ID)
     call constitutive_j2_LpAndItsTangent(Lp,dLp_dTstar,Tstar_v,constitutive_state,ipc,ip,el)
    
   case (PLASTICITY_PHENOPOWERLAW_ID)
     call constitutive_phenopowerlaw_LpAndItsTangent(Lp,dLp_dTstar,Tstar_v,constitutive_state,ipc,ip,el)
    
   case (PLASTICITY_DISLOTWIN_ID)
     call constitutive_dislotwin_LpAndItsTangent(Lp,dLp_dTstar,Tstar_v,temperature,constitutive_state,ipc,ip,el)
   
   case (PLASTICITY_TITANMOD_ID)
     call constitutive_titanmod_LpAndItsTangent(Lp,dLp_dTstar,Tstar_v,temperature,constitutive_state,ipc,ip,el)
    
   case (PLASTICITY_NONLOCAL_ID)
     call constitutive_nonlocal_LpAndItsTangent(Lp, dLp_dTstar, Tstar_v, temperature, constitutive_state(ipc,ip,el), ipc,ip,el)
    
 end select
 
end subroutine constitutive_LpAndItsTangent



!--------------------------------------------------------------------------------------------------
!> @brief returns the 2nd Piola-Kirchhoff stress tensor and its tangent with respect to 
!> the elastic deformation gradient depending on the selected elastic law (so far no case switch
!! because only hooke is implemented
!--------------------------------------------------------------------------------------------------
pure subroutine constitutive_TandItsTangent(T, dT_dFe, Fe, ipc, ip, el)
 
 implicit none
 integer(pInt), intent(in) :: &
   ipc, &                                                                                           !< grain number
   ip, &                                                                                            !< integration point number
   el                                                                                               !< element number
 real(pReal),   intent(in),  dimension(3,3) :: &
   Fe                                                                                               !< elastic deformation gradient
 real(pReal),   intent(out), dimension(3,3) :: &
   T                                                                                                !< 2nd Piola-Kirchhoff stress tensor
 real(pReal),   intent(out), dimension(3,3,3,3) :: &
   dT_dFe                                                                                           !< derivative of 2nd P-K stress with respect to elastic deformation gradient
 
 call constitutive_hooke_TandItsTangent(T, dT_dFe, Fe, ipc, ip, el)

 
end subroutine constitutive_TandItsTangent


!--------------------------------------------------------------------------------------------------
!> @brief returns the 2nd Piola-Kirchhoff stress tensor and its tangent with respect to 
!> the elastic deformation gradient using hookes law
!--------------------------------------------------------------------------------------------------
pure subroutine constitutive_hooke_TandItsTangent(T, dT_dFe, Fe, ipc, ip, el)
use math, only : &
  math_mul3x3, &
  math_mul33x33, &
  math_mul3333xx33, &
  math_Mandel66to3333, &
  math_transpose33, &
  MATH_I3

 implicit none
 integer(pInt), intent(in) :: &
   ipc, &                                                                                           !< grain number
   ip, &                                                                                            !< integration point number
   el                                                                                               !< element number
 real(pReal),   intent(in),  dimension(3,3) :: &
   Fe                                                                                               !< elastic deformation gradient
 real(pReal),   intent(out), dimension(3,3) :: &
   T                                                                                                !< 2nd Piola-Kirchhoff stress tensor
 real(pReal),   intent(out), dimension(3,3,3,3) :: & 
   dT_dFe                                                                                           !< dT/dFe
 
 integer(pInt) :: i, j, k, l
 real(pReal), dimension(3,3)     :: FeT
 real(pReal), dimension(3,3,3,3) :: C


 C = math_Mandel66to3333(constitutive_homogenizedC(ipc,ip,el))

 FeT = math_transpose33(Fe)
 T = 0.5_pReal * math_mul3333xx33(C, math_mul33x33(FeT,Fe)-MATH_I3)

 dT_dFe = 0.0_pReal
 forall (i=1_pInt:3_pInt, j=1_pInt:3_pInt, k=1_pInt:3_pInt, l=1_pInt:3_pInt) &
   dT_dFe(i,j,k,l) = math_mul3x3(C(i,j,l,1:3),Fe(k,1:3))                                            ! dT*_ij/dFe_kl

end subroutine constitutive_hooke_TandItsTangent


!--------------------------------------------------------------------------------------------------
!> @brief contains the constitutive equation for calculating the rate of change of microstructure 
!--------------------------------------------------------------------------------------------------
subroutine constitutive_collectDotState(Tstar_v, Fe, Fp, Temperature, subdt, subfrac, ipc, ip, el)
 use prec, only: &
   pLongInt
 use debug, only: &
   debug_cumDotStateCalls, &
   debug_cumDotStateTicks, &
   debug_level, &
   debug_constitutive, &
   debug_levelBasic
 use mesh, only: &
   mesh_NcpElems, &
   mesh_maxNips
 use material, only: &
   phase_plasticity, &
   material_phase, &
   homogenization_maxNgrains, &
   PLASTICITY_NONE_ID, &
   PLASTICITY_J2_ID, &
   PLASTICITY_PHENOPOWERLAW_ID, &
   PLASTICITY_DISLOTWIN_ID, &
   PLASTICITY_TITANMOD_ID, &
   PLASTICITY_NONLOCAL_ID
 use constitutive_j2, only:  &
   constitutive_j2_dotState
 use constitutive_phenopowerlaw, only: &
   constitutive_phenopowerlaw_dotState
 use constitutive_dislotwin, only: &
   constitutive_dislotwin_dotState
 use constitutive_titanmod, only: &
   constitutive_titanmod_dotState
 use constitutive_nonlocal, only: &
   constitutive_nonlocal_dotState
 
 implicit none
 integer(pInt), intent(in) :: &
   ipc, &                                                                                           !< grain number
   ip, &                                                                                            !< integration point number
   el                                                                                               !< element number
 real(pReal),  intent(in) :: &
   Temperature, &
   subdt                                                                                            !< timestep
 real(pReal),  intent(in), dimension(homogenization_maxNgrains,mesh_maxNips,mesh_NcpElems) :: &
   subfrac                                                                                          !< subfraction of timestep
 real(pReal),  intent(in), dimension(3,3,homogenization_maxNgrains,mesh_maxNips,mesh_NcpElems) :: &
   Fe, &                                                                                            !< elastic deformation gradient
   Fp                                                                                               !< plastic deformation gradient
 real(pReal),  intent(in), dimension(6) :: &
   Tstar_v                                                                                          !< 2nd Piola Kirchhoff stress tensor (Mandel)
 integer(pLongInt) :: &
   tick, tock, & 
   tickrate, &
   maxticks
 
 if (iand(debug_level(debug_constitutive), debug_levelBasic) /= 0_pInt) &
   call system_clock(count=tick,count_rate=tickrate,count_max=maxticks)
 
 select case (phase_plasticity(material_phase(ipc,ip,el)))
 
   case (PLASTICITY_NONE_ID)
     constitutive_dotState(ipc,ip,el)%p = 0.0_pReal !ToDo: needed or will it remain zero anyway?
  
   case (PLASTICITY_J2_ID)
     constitutive_dotState(ipc,ip,el)%p = constitutive_j2_dotState(Tstar_v,constitutive_state,ipc,ip,el)
  
   case (PLASTICITY_PHENOPOWERLAW_ID)
     constitutive_dotState(ipc,ip,el)%p = constitutive_phenopowerlaw_dotState(Tstar_v,constitutive_state,ipc,ip,el)
 
   case (PLASTICITY_TITANMOD_ID)
     constitutive_dotState(ipc,ip,el)%p = constitutive_titanmod_dotState(Tstar_v,Temperature,constitutive_state,ipc,ip,el)
   
   case (PLASTICITY_DISLOTWIN_ID)
     constitutive_dotState(ipc,ip,el)%p = constitutive_dislotwin_dotState(Tstar_v,Temperature,constitutive_state,ipc,ip,el)
  
   case (PLASTICITY_NONLOCAL_ID)
     constitutive_dotState(ipc,ip,el)%p = constitutive_nonlocal_dotState(Tstar_v, Fe, Fp, Temperature, constitutive_state, &
                                                                       constitutive_state0, subdt, subfrac, ipc, ip, el)
 
 end select
 
 if (iand(debug_level(debug_constitutive), debug_levelBasic) /= 0_pInt) then
   call system_clock(count=tock,count_rate=tickrate,count_max=maxticks)
   !$OMP CRITICAL (debugTimingDotState)
     debug_cumDotStateCalls = debug_cumDotStateCalls + 1_pInt
     debug_cumDotStateTicks = debug_cumDotStateTicks + tock-tick
     !$OMP FLUSH (debug_cumDotStateTicks)
     if (tock < tick) debug_cumDotStateTicks  = debug_cumDotStateTicks + maxticks
   !$OMP END CRITICAL (debugTimingDotState)
 endif
 
end subroutine constitutive_collectDotState


!--------------------------------------------------------------------------------------------------
!> @brief contains the constitutive equation for calculating the incremental change of 
!> microstructure based on the current stress and state  
!--------------------------------------------------------------------------------------------------
subroutine constitutive_collectDeltaState(Tstar_v, ipc, ip, el)
 use prec, only: &
   pLongInt
 use debug, only: &
   debug_cumDeltaStateCalls, &
   debug_cumDeltaStateTicks, &
   debug_level, &
   debug_constitutive, &
   debug_levelBasic
 use material, only: &
   phase_plasticity, &
   material_phase, &
   PLASTICITY_NONLOCAL_ID
 use constitutive_nonlocal, only: &
   constitutive_nonlocal_deltaState
 
 implicit none
 integer(pInt), intent(in) :: &
   ipc, &                                                                                           !< grain number
   ip, &                                                                                            !< integration point number
   el                                                                                               !< element number
 real(pReal),   intent(in),  dimension(6) :: &
   Tstar_v                                                                                          !< 2nd Piola-Kirchhoff stress     
 integer(pLongInt) :: &
   tick, tock, & 
   tickrate, &
   maxticks

 if (iand(debug_level(debug_constitutive), debug_levelBasic) /= 0_pInt) &
   call system_clock(count=tick,count_rate=tickrate,count_max=maxticks)

 select case (phase_plasticity(material_phase(ipc,ip,el)))

   case (PLASTICITY_NONLOCAL_ID)
     call constitutive_nonlocal_deltaState(constitutive_deltaState(ipc,ip,el),constitutive_state, Tstar_v,ipc,ip,el)

   case default
     constitutive_deltaState(ipc,ip,el)%p = 0.0_pReal !ToDo: needed or will it remain zero anyway?
 
 end select

 if (iand(debug_level(debug_constitutive), debug_levelBasic) /= 0_pInt) then
   call system_clock(count=tock,count_rate=tickrate,count_max=maxticks)
   !$OMP CRITICAL (debugTimingDeltaState)
     debug_cumDeltaStateCalls = debug_cumDeltaStateCalls + 1_pInt
     debug_cumDeltaStateTicks = debug_cumDeltaStateTicks + tock-tick
     !$OMP FLUSH (debug_cumDeltaStateTicks)
     if (tock < tick) debug_cumDeltaStateTicks  = debug_cumDeltaStateTicks + maxticks
   !$OMP END CRITICAL (debugTimingDeltaState)
 endif

end subroutine constitutive_collectDeltaState


!--------------------------------------------------------------------------------------------------
!> @brief returns array of constitutive results
!--------------------------------------------------------------------------------------------------
function constitutive_postResults(Tstar_v, Fe, temperature, ipc, ip, el)
 use mesh, only: &
   mesh_NcpElems, &
   mesh_maxNips
 use material, only: &
   phase_plasticity, &
   material_phase, &
   homogenization_maxNgrains, &
   PLASTICITY_NONE_ID, &
   PLASTICITY_J2_ID, &
   PLASTICITY_PHENOPOWERLAW_ID, &
   PLASTICITY_DISLOTWIN_ID, &
   PLASTICITY_TITANMOD_ID, &
   PLASTICITY_NONLOCAL_ID
 use constitutive_j2, only: &
   constitutive_j2_postResults
 use constitutive_phenopowerlaw, only: &
   constitutive_phenopowerlaw_postResults 
 use constitutive_dislotwin, only: &
   constitutive_dislotwin_postResults
 use constitutive_titanmod, only: &
   constitutive_titanmod_postResults
 use constitutive_nonlocal, only: &
   constitutive_nonlocal_postResults
 
 implicit none
 integer(pInt), intent(in) :: &
   ipc, &                                                                                           !< grain number
   ip, &                                                                                            !< integration point number
   el                                                                                               !< element number
 real(pReal), dimension(constitutive_sizePostResults(ipc,ip,el)) :: &
   constitutive_postResults
 real(pReal),  intent(in) :: &
   temperature
 real(pReal),  intent(in), dimension(3,3,homogenization_maxNgrains,mesh_maxNips,mesh_NcpElems) :: &
   Fe                                                                                               !< elastic deformation gradient
 real(pReal),  intent(in), dimension(6) :: &
   Tstar_v                                                                                          !< 2nd Piola Kirchhoff stress tensor (Mandel)

 constitutive_postResults = 0.0_pReal
 
 select case (phase_plasticity(material_phase(ipc,ip,el)))
 
   case (PLASTICITY_NONE_ID)
     constitutive_postResults = 0.0_pReal
    
   case (PLASTICITY_TITANMOD_ID)
     constitutive_postResults = constitutive_titanmod_postResults(constitutive_state,ipc,ip,el)
    
   case (PLASTICITY_J2_ID)
     constitutive_postResults = constitutive_j2_postResults(Tstar_v,constitutive_state,ipc,ip,el)
    
   case (PLASTICITY_PHENOPOWERLAW_ID)
     constitutive_postResults = constitutive_phenopowerlaw_postResults(Tstar_v,constitutive_state,ipc,ip,el)
   
   case (PLASTICITY_DISLOTWIN_ID)
     constitutive_postResults = constitutive_dislotwin_postResults(Tstar_v,Temperature,constitutive_state,ipc,ip,el)
    
   case (PLASTICITY_NONLOCAL_ID)
     constitutive_postResults = constitutive_nonlocal_postResults(Tstar_v, Fe, constitutive_state, &
                                                                  constitutive_dotstate(ipc,ip,el), ipc, ip, el)
 end select
  
end function constitutive_postResults


end module constitutive
