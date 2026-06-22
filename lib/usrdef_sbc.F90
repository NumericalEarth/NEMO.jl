MODULE usrdef_sbc
   !!======================================================================
   !!                     ***  MODULE usrdef_sbc  ***
   !!
   !!   NEMO.jl external surface forcing
   !!
   !! The ocean surface momentum, heat, and freshwater fluxes (utau, vtau,
   !! qns, qsr, emp, sfx) are provided externally — set from Julia through the
   !! wrapper's set_*! routines — and are left untouched here, so an external
   !! driver (e.g. NumericalEarth) owns the surface boundary condition. The
   !! wind-stress module taum and wind module wndm are derived from the
   !! externally-set stress so wind-dependent physics stays consistent.
   !!
   !! Enabled by NEMO.jl when a configuration is built with `external_forcing
   !! = true`; requires `ln_usr = .true.` in namsbc (applied automatically by
   !! `setup_run_directory`).
   !!======================================================================
   USE oce             ! ocean dynamics and tracers
   USE dom_oce         ! ocean space and time domain
   USE sbc_oce         ! surface boundary condition: ocean fields
   USE phycst          ! physical constants
   USE in_out_manager  ! I/O manager
   USE lib_mpp         ! distributed memory computing library
   USE lbclnk          ! ocean lateral boundary conditions (or mpp link)
   USE lib_fortran     ! Fortran utilities

   IMPLICIT NONE
   PRIVATE

   PUBLIC   usrdef_sbc_oce      ! routine called in sbcmod module
   PUBLIC   usrdef_sbc_ice_tau  ! routine called by icestp.F90 for ice dynamics
   PUBLIC   usrdef_sbc_ice_flx  ! routine called by icestp.F90 for ice thermo

CONTAINS

   SUBROUTINE usrdef_sbc_oce( kt, Kbb )
      !!---------------------------------------------------------------------
      !! ** Purpose :   keep the externally-provided surface fluxes and derive
      !!                the consistent wind-stress and wind modules.
      !!---------------------------------------------------------------------
      INTEGER, INTENT(in) ::   kt        ! ocean time step
      INTEGER, INTENT(in) ::   Kbb       ! ocean time index
      INTEGER  ::   ji, jj               ! dummy loop indices
      REAL(wp) ::   zrhoair = 1.22_wp    ! approximate air density   [kg/m3]
      REAL(wp) ::   zcd     = 1.13e-3_wp ! approximate drag coefficient
      REAL(wp) ::   ztx, zty             ! wind stress at T-point
      !!---------------------------------------------------------------------
      !
      ! utau, vtau, qns, qsr, emp, sfx are owned by the external driver — never overwrite them here.
      ! Refresh the wind-stress halos and rebuild taum / wndm from the externally-set stress.
      CALL lbc_lnk( 'usrdef_sbc', utau, 'U', -1._wp, vtau, 'V', -1._wp )
      !
      DO jj = 2, jpj
         DO ji = 2, jpi
            ztx = 0.5_wp * ( utau(ji-1,jj) + utau(ji,jj) )
            zty = 0.5_wp * ( vtau(ji,jj-1) + vtau(ji,jj) )
            taum(ji,jj) = SQRT( ztx * ztx + zty * zty )
         END DO
      END DO
      CALL lbc_lnk( 'usrdef_sbc', taum, 'T', 1._wp )
      wndm(:,:) = SQRT( taum(:,:) / ( zrhoair * zcd ) )
      !
   END SUBROUTINE usrdef_sbc_oce

   SUBROUTINE usrdef_sbc_ice_tau( kt )
      INTEGER, INTENT(in) ::   kt   ! ocean time step
   END SUBROUTINE usrdef_sbc_ice_tau

   SUBROUTINE usrdef_sbc_ice_flx( kt, phs, phi )
      INTEGER, INTENT(in) ::   kt   ! ocean time step
      REAL(wp), DIMENSION(:,:,:), INTENT(in)  ::   phs    ! snow thickness
      REAL(wp), DIMENSION(:,:,:), INTENT(in)  ::   phi    ! ice thickness
   END SUBROUTINE usrdef_sbc_ice_flx

   !!======================================================================
END MODULE usrdef_sbc
