!--------------------------------------------------------------------------------------------------
!> @author Martin Diehl, KU Leuven
!--------------------------------------------------------------------------------------------------
submodule(homogenization) thermal

  interface

    module subroutine pass_init
    end subroutine pass_init

    module subroutine isotemperature_init
    end subroutine isotemperature_init

  end interface

  type :: tDataContainer
    real(pReal), dimension(:), allocatable :: T, dot_T
  end type tDataContainer

  type(tDataContainer), dimension(:), allocatable :: current

  type :: tParameters
    character(len=pStringLen), allocatable, dimension(:) :: &
      output
  end type tParameters

  type(tparameters),             dimension(:), allocatable :: &
    param


contains

!--------------------------------------------------------------------------------------------------
!> @brief Allocate variables and set parameters.
!--------------------------------------------------------------------------------------------------
module subroutine thermal_init()

  type(tDict), pointer :: &
    configHomogenizations, &
    configHomogenization, &
    configHomogenizationThermal
  integer :: ho


  print'(/,1x,a)', '<<<+-  homogenization:thermal init  -+>>>'


  configHomogenizations => config_material%get_dict('homogenization')
  allocate(param(configHomogenizations%length))
  allocate(current(configHomogenizations%length))

  do ho = 1, configHomogenizations%length
    allocate(current(ho)%T(count(material_homogenizationID==ho)), source=T_ROOM)
    allocate(current(ho)%dot_T(count(material_homogenizationID==ho)), source=0.0_pReal)
    configHomogenization => configHomogenizations%get_dict(ho)
    associate(prm => param(ho))

      if (configHomogenization%contains('thermal')) then
        configHomogenizationThermal => configHomogenization%get_dict('thermal')
#if defined (__GFORTRAN__)
        prm%output = output_as1dString(configHomogenizationThermal)
#else
        prm%output = configHomogenizationThermal%get_as1dString('output',defaultVal=emptyStringArray)
#endif
        select case (configHomogenizationThermal%get_asString('type'))

          case ('pass')
            call pass_init()

          case ('isotemperature')
            call isotemperature_init()

        end select
      else
        prm%output = emptyStringArray
      end if

    end associate
  end do

end subroutine thermal_init


!--------------------------------------------------------------------------------------------------
!> @brief Check if thermal homogemization description is present in the configuration file
!--------------------------------------------------------------------------------------------------
module function homogenization_thermal_active() result(active)

  logical :: active

  active = any(thermal_active(:))

end function homogenization_thermal_active


!--------------------------------------------------------------------------------------------------
!> @brief Partition temperature onto the individual constituents.
!--------------------------------------------------------------------------------------------------
module subroutine thermal_partition(ce)

  integer, intent(in) :: ce

  real(pReal) :: T, dot_T
  integer :: co


  T     = current(material_homogenizationID(ce))%T(material_homogenizationEntry(ce))
  dot_T = current(material_homogenizationID(ce))%dot_T(material_homogenizationEntry(ce))
  do co = 1, homogenization_Nconstituents(material_homogenizationID(ce))
    call phase_thermal_setField(T,dot_T,co,ce)
  end do

end subroutine thermal_partition


!--------------------------------------------------------------------------------------------------
!> @brief Homogenize thermal viscosity.
!--------------------------------------------------------------------------------------------------
module function homogenization_mu_T(ce) result(mu)

  integer, intent(in) :: ce
  real(pReal) :: mu

  integer :: co


  mu = phase_mu_T(1,ce)*material_v(1,ce)
  do co = 2, homogenization_Nconstituents(material_homogenizationID(ce))
    mu = mu + phase_mu_T(co,ce)*material_v(co,ce)
  end do

end function homogenization_mu_T


!--------------------------------------------------------------------------------------------------
!> @brief Homogenize thermal conductivity.
!--------------------------------------------------------------------------------------------------
module function homogenization_K_T(ce) result(K)

  integer, intent(in) :: ce
  real(pReal), dimension(3,3) :: K

  integer :: co


  K = phase_K_T(1,ce)*material_v(1,ce)
  do co = 2, homogenization_Nconstituents(material_homogenizationID(ce))
    K = K + phase_K_T(co,ce)*material_v(co,ce)
  end do

end function homogenization_K_T


!--------------------------------------------------------------------------------------------------
!> @brief Homogenize heat generation rate.
!--------------------------------------------------------------------------------------------------
module function homogenization_f_T(ce) result(f)

  integer, intent(in) :: ce
  real(pReal) :: f

  integer :: co


  f = phase_f_T(material_phaseID(1,ce),material_phaseEntry(1,ce))*material_v(1,ce)
  do co = 2, homogenization_Nconstituents(material_homogenizationID(ce))
    f = f + phase_f_T(material_phaseID(co,ce),material_phaseEntry(co,ce))*material_v(co,ce)
  end do

end function homogenization_f_T


!--------------------------------------------------------------------------------------------------
!> @brief Set thermal field and its rate (T and dot_T).
!--------------------------------------------------------------------------------------------------
module subroutine homogenization_thermal_setField(T,dot_T, ce)

  integer, intent(in) :: ce
  real(pReal), intent(in) :: T, dot_T


  current(material_homogenizationID(ce))%T(material_homogenizationEntry(ce)) = T
  current(material_homogenizationID(ce))%dot_T(material_homogenizationEntry(ce)) = dot_T
  call thermal_partition(ce)

end subroutine homogenization_thermal_setField


!--------------------------------------------------------------------------------------------------
!> @brief writes results to HDF5 output file
!--------------------------------------------------------------------------------------------------
module subroutine thermal_result(ho,group)

  integer,          intent(in) :: ho
  character(len=*), intent(in) :: group

  integer :: o


  associate(prm => param(ho))
    outputsLoop: do o = 1,size(prm%output)
      select case(trim(prm%output(o)))
        case('T')
          call result_writeDataset(current(ho)%T,group,'T','temperature','K')
      end select
    end do outputsLoop
  end associate

end subroutine thermal_result

end submodule thermal
