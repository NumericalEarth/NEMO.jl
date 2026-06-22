MODULE nemo_julia_wrapper

   USE, INTRINSIC :: iso_c_binding, ONLY : c_int, c_double, c_char, c_null_char

   USE par_kind,       ONLY : wp, dp
   USE par_oce,        ONLY : jp_tem, jp_sal, jpi, jpj, jpk,                    &
                              Nis0, Nie0, Njs0, Nje0
   USE dom_oce,        ONLY : glamt, gphit, gdept_0,                            &
                              e1t, e2t, mbkt, rDt, rn_Dt
   USE oce,            ONLY : ts, uu, vv, ww, ssh
   USE sbc_oce,        ONLY : utau, vtau, qns, qsr, emp, sfx
   USE nemogcm,        ONLY : nemo_init
   USE iom,            ONLY : iom_close
   USE lib_mpp,        ONLY : mppstop
#if defined key_qco || defined key_linssh
   USE stpmlf,         ONLY : stp_MLF, Nnn
#else
   USE step,           ONLY : stp, Nnn
#endif
   USE in_out_manager, ONLY : nit000, nitend, numout, lwp, numnul, numstp, numrun, numond

   IMPLICIT NONE
   PRIVATE

   INTEGER, SAVE :: current_step = 0

CONTAINS

   SUBROUTINE nemo_internal_init(mpi_communicator) BIND(C, name='nemo_internal_init')
      INTEGER(c_int), VALUE, INTENT(in) :: mpi_communicator

      CALL nemo_init

      current_step = nit000 - 1
   END SUBROUTINE nemo_internal_init


   SUBROUTINE nemo_internal_step() BIND(C, name='nemo_internal_step')
      current_step = current_step + 1
#if defined key_qco || defined key_linssh
      CALL stp_MLF(current_step)
#else
      CALL stp(current_step)
#endif
   END SUBROUTINE nemo_internal_step


   SUBROUTINE nemo_internal_finalize() BIND(C, name='nemo_internal_finalize')
      CALL iom_close
      ! Close NEMO's persistent Fortran units so the model can be re-initialized in the same process. The
      ! dlopen'd library copies share a single libgfortran unit table, so a leaked unit — in particular
      ! numnul (/dev/null), which NEMO's own nemo_closefile does not close — makes the next nemo_init STOP.
      IF( numnul /= -1 )   CLOSE( numnul )
      IF( numout /=  6 )   CLOSE( numout )
      IF( numstp /= -1 )   CLOSE( numstp )
      IF( numrun /= -1 )   CLOSE( numrun )
      IF( numond /= -1 )   CLOSE( numond )
      numnul = -1   ;   numout = 6   ;   numstp = -1   ;   numrun = -1   ;   numond = -1
      CALL mppstop
   END SUBROUTINE nemo_internal_finalize


   SUBROUTINE nemo_get_grid_size(jpi_out, jpj_out, jpk_out,                     &
                                 Nis0_out, Nie0_out, Njs0_out, Nje0_out)        &
              BIND(C, name='nemo_get_grid_size')
      INTEGER(c_int), INTENT(out) :: jpi_out, jpj_out, jpk_out
      INTEGER(c_int), INTENT(out) :: Nis0_out, Nie0_out, Njs0_out, Nje0_out

      jpi_out  = jpi
      jpj_out  = jpj
      jpk_out  = jpk
      Nis0_out = Nis0
      Nie0_out = Nie0
      Njs0_out = Njs0
      Nje0_out = Nje0
   END SUBROUTINE nemo_get_grid_size


   SUBROUTINE nemo_get_iteration_count(count) BIND(C, name='nemo_get_iteration_count')
      INTEGER(c_int), INTENT(out) :: count
      count = current_step
   END SUBROUTINE nemo_get_iteration_count


   SUBROUTINE nemo_get_simulation_time(time) BIND(C, name='nemo_get_simulation_time')
      REAL(c_double), INTENT(out) :: time
      time = REAL(current_step, c_double) * REAL(rn_Dt, c_double)
   END SUBROUTINE nemo_get_simulation_time


   SUBROUTINE nemo_get_timestep(timestep) BIND(C, name='nemo_get_timestep')
      REAL(c_double), INTENT(out) :: timestep
      timestep = REAL(rn_Dt, c_double)
   END SUBROUTINE nemo_get_timestep


   SUBROUTINE nemo_set_timestep(timestep) BIND(C, name='nemo_set_timestep')
      REAL(c_double), VALUE, INTENT(in) :: timestep
      rn_Dt = REAL(timestep, wp)
      rDt   = REAL(timestep, wp)
   END SUBROUTINE nemo_set_timestep


   SUBROUTINE nemo_get_working_precision(bytes) BIND(C, name='nemo_get_working_precision')
      INTEGER(c_int), INTENT(out) :: bytes
      bytes = wp
   END SUBROUTINE nemo_get_working_precision


   SUBROUTINE copy_3d_to_c(field, array_out)
      REAL(wp),       INTENT(in)  :: field(jpi, jpj, jpk)
      REAL(c_double), INTENT(out) :: array_out(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1, jpk)
      INTEGER :: i, j, k
      DO k = 1, jpk
         DO j = 1, Nje0 - Njs0 + 1
            DO i = 1, Nie0 - Nis0 + 1
               array_out(i, j, k) = REAL(field(Nis0 + i - 1, Njs0 + j - 1, k), c_double)
            END DO
         END DO
      END DO
   END SUBROUTINE copy_3d_to_c


   SUBROUTINE copy_3d_from_c(array_in, field)
      REAL(c_double), INTENT(in)    :: array_in(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1, jpk)
      REAL(wp),       INTENT(inout) :: field(jpi, jpj, jpk)
      INTEGER :: i, j, k
      DO k = 1, jpk
         DO j = 1, Nje0 - Njs0 + 1
            DO i = 1, Nie0 - Nis0 + 1
               field(Nis0 + i - 1, Njs0 + j - 1, k) = REAL(array_in(i, j, k), wp)
            END DO
         END DO
      END DO
   END SUBROUTINE copy_3d_from_c


   SUBROUTINE copy_2d_to_c(field, array_out)
      REAL(wp),       INTENT(in)  :: field(jpi, jpj)
      REAL(c_double), INTENT(out) :: array_out(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1)
      INTEGER :: i, j
      DO j = 1, Nje0 - Njs0 + 1
         DO i = 1, Nie0 - Nis0 + 1
            array_out(i, j) = REAL(field(Nis0 + i - 1, Njs0 + j - 1), c_double)
         END DO
      END DO
   END SUBROUTINE copy_2d_to_c


   SUBROUTINE copy_2d_from_c(array_in, field)
      REAL(c_double), INTENT(in)    :: array_in(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1)
      REAL(wp),       INTENT(inout) :: field(jpi, jpj)
      INTEGER :: i, j
      DO j = 1, Nje0 - Njs0 + 1
         DO i = 1, Nie0 - Nis0 + 1
            field(Nis0 + i - 1, Njs0 + j - 1) = REAL(array_in(i, j), wp)
         END DO
      END DO
   END SUBROUTINE copy_2d_from_c


   SUBROUTINE copy_int_2d_to_c(field, array_out)
      INTEGER,        INTENT(in)  :: field(jpi, jpj)
      INTEGER(c_int), INTENT(out) :: array_out(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1)
      INTEGER :: i, j
      DO j = 1, Nje0 - Njs0 + 1
         DO i = 1, Nie0 - Nis0 + 1
            array_out(i, j) = field(Nis0 + i - 1, Njs0 + j - 1)
         END DO
      END DO
   END SUBROUTINE copy_int_2d_to_c


   SUBROUTINE nemo_get_temperature(array_out) BIND(C, name='nemo_get_temperature')
      REAL(c_double), INTENT(out) :: array_out(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1, jpk)
      CALL copy_3d_to_c(ts(:,:,:, jp_tem, Nnn), array_out)
   END SUBROUTINE nemo_get_temperature


   SUBROUTINE nemo_set_temperature(array_in) BIND(C, name='nemo_set_temperature')
      REAL(c_double), INTENT(in) :: array_in(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1, jpk)
      CALL copy_3d_from_c(array_in, ts(:,:,:, jp_tem, Nnn))
   END SUBROUTINE nemo_set_temperature


   SUBROUTINE nemo_get_salinity(array_out) BIND(C, name='nemo_get_salinity')
      REAL(c_double), INTENT(out) :: array_out(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1, jpk)
      CALL copy_3d_to_c(ts(:,:,:, jp_sal, Nnn), array_out)
   END SUBROUTINE nemo_get_salinity


   SUBROUTINE nemo_set_salinity(array_in) BIND(C, name='nemo_set_salinity')
      REAL(c_double), INTENT(in) :: array_in(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1, jpk)
      CALL copy_3d_from_c(array_in, ts(:,:,:, jp_sal, Nnn))
   END SUBROUTINE nemo_set_salinity


   SUBROUTINE nemo_get_zonal_velocity(array_out) BIND(C, name='nemo_get_zonal_velocity')
      REAL(c_double), INTENT(out) :: array_out(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1, jpk)
      CALL copy_3d_to_c(uu(:,:,:, Nnn), array_out)
   END SUBROUTINE nemo_get_zonal_velocity


   SUBROUTINE nemo_set_zonal_velocity(array_in) BIND(C, name='nemo_set_zonal_velocity')
      REAL(c_double), INTENT(in) :: array_in(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1, jpk)
      CALL copy_3d_from_c(array_in, uu(:,:,:, Nnn))
   END SUBROUTINE nemo_set_zonal_velocity


   SUBROUTINE nemo_get_meridional_velocity(array_out) BIND(C, name='nemo_get_meridional_velocity')
      REAL(c_double), INTENT(out) :: array_out(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1, jpk)
      CALL copy_3d_to_c(vv(:,:,:, Nnn), array_out)
   END SUBROUTINE nemo_get_meridional_velocity


   SUBROUTINE nemo_set_meridional_velocity(array_in) BIND(C, name='nemo_set_meridional_velocity')
      REAL(c_double), INTENT(in) :: array_in(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1, jpk)
      CALL copy_3d_from_c(array_in, vv(:,:,:, Nnn))
   END SUBROUTINE nemo_set_meridional_velocity


   SUBROUTINE nemo_get_vertical_velocity(array_out) BIND(C, name='nemo_get_vertical_velocity')
      REAL(c_double), INTENT(out) :: array_out(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1, jpk)
      CALL copy_3d_to_c(ww, array_out)
   END SUBROUTINE nemo_get_vertical_velocity


   SUBROUTINE nemo_get_sea_surface_height(array_out) BIND(C, name='nemo_get_sea_surface_height')
      REAL(c_double), INTENT(out) :: array_out(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1)
      CALL copy_2d_to_c(ssh(:,:, Nnn), array_out)
   END SUBROUTINE nemo_get_sea_surface_height


   SUBROUTINE nemo_set_sea_surface_height(array_in) BIND(C, name='nemo_set_sea_surface_height')
      REAL(c_double), INTENT(in) :: array_in(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1)
      CALL copy_2d_from_c(array_in, ssh(:,:, Nnn))
   END SUBROUTINE nemo_set_sea_surface_height


   SUBROUTINE nemo_get_zonal_wind_stress(array_out) BIND(C, name='nemo_get_zonal_wind_stress')
      REAL(c_double), INTENT(out) :: array_out(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1)
      CALL copy_2d_to_c(utau, array_out)
   END SUBROUTINE nemo_get_zonal_wind_stress


   SUBROUTINE nemo_set_zonal_wind_stress(array_in) BIND(C, name='nemo_set_zonal_wind_stress')
      REAL(c_double), INTENT(in) :: array_in(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1)
      CALL copy_2d_from_c(array_in, utau)
   END SUBROUTINE nemo_set_zonal_wind_stress


   SUBROUTINE nemo_get_meridional_wind_stress(array_out) BIND(C, name='nemo_get_meridional_wind_stress')
      REAL(c_double), INTENT(out) :: array_out(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1)
      CALL copy_2d_to_c(vtau, array_out)
   END SUBROUTINE nemo_get_meridional_wind_stress


   SUBROUTINE nemo_set_meridional_wind_stress(array_in) BIND(C, name='nemo_set_meridional_wind_stress')
      REAL(c_double), INTENT(in) :: array_in(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1)
      CALL copy_2d_from_c(array_in, vtau)
   END SUBROUTINE nemo_set_meridional_wind_stress


   SUBROUTINE nemo_get_nonsolar_heat_flux(array_out) BIND(C, name='nemo_get_nonsolar_heat_flux')
      REAL(c_double), INTENT(out) :: array_out(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1)
      CALL copy_2d_to_c(qns, array_out)
   END SUBROUTINE nemo_get_nonsolar_heat_flux


   SUBROUTINE nemo_set_nonsolar_heat_flux(array_in) BIND(C, name='nemo_set_nonsolar_heat_flux')
      REAL(c_double), INTENT(in) :: array_in(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1)
      CALL copy_2d_from_c(array_in, qns)
   END SUBROUTINE nemo_set_nonsolar_heat_flux


   SUBROUTINE nemo_get_solar_radiation(array_out) BIND(C, name='nemo_get_solar_radiation')
      REAL(c_double), INTENT(out) :: array_out(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1)
      CALL copy_2d_to_c(qsr, array_out)
   END SUBROUTINE nemo_get_solar_radiation


   SUBROUTINE nemo_set_solar_radiation(array_in) BIND(C, name='nemo_set_solar_radiation')
      REAL(c_double), INTENT(in) :: array_in(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1)
      CALL copy_2d_from_c(array_in, qsr)
   END SUBROUTINE nemo_set_solar_radiation


   SUBROUTINE nemo_get_freshwater_flux(array_out) BIND(C, name='nemo_get_freshwater_flux')
      REAL(c_double), INTENT(out) :: array_out(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1)
      CALL copy_2d_to_c(emp, array_out)
   END SUBROUTINE nemo_get_freshwater_flux


   SUBROUTINE nemo_set_freshwater_flux(array_in) BIND(C, name='nemo_set_freshwater_flux')
      REAL(c_double), INTENT(in) :: array_in(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1)
      CALL copy_2d_from_c(array_in, emp)
   END SUBROUTINE nemo_set_freshwater_flux


   SUBROUTINE nemo_get_salt_flux(array_out) BIND(C, name='nemo_get_salt_flux')
      REAL(c_double), INTENT(out) :: array_out(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1)
      CALL copy_2d_to_c(sfx, array_out)
   END SUBROUTINE nemo_get_salt_flux


   SUBROUTINE nemo_set_salt_flux(array_in) BIND(C, name='nemo_set_salt_flux')
      REAL(c_double), INTENT(in) :: array_in(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1)
      CALL copy_2d_from_c(array_in, sfx)
   END SUBROUTINE nemo_set_salt_flux


   SUBROUTINE nemo_get_cell_longitude(array_out) BIND(C, name='nemo_get_cell_longitude')
      REAL(c_double), INTENT(out) :: array_out(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1)
      CALL copy_2d_to_c(glamt, array_out)
   END SUBROUTINE nemo_get_cell_longitude


   SUBROUTINE nemo_get_cell_latitude(array_out) BIND(C, name='nemo_get_cell_latitude')
      REAL(c_double), INTENT(out) :: array_out(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1)
      CALL copy_2d_to_c(gphit, array_out)
   END SUBROUTINE nemo_get_cell_latitude


   SUBROUTINE nemo_get_cell_zonal_size(array_out) BIND(C, name='nemo_get_cell_zonal_size')
      REAL(c_double), INTENT(out) :: array_out(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1)
      CALL copy_2d_to_c(e1t, array_out)
   END SUBROUTINE nemo_get_cell_zonal_size


   SUBROUTINE nemo_get_cell_meridional_size(array_out) BIND(C, name='nemo_get_cell_meridional_size')
      REAL(c_double), INTENT(out) :: array_out(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1)
      CALL copy_2d_to_c(e2t, array_out)
   END SUBROUTINE nemo_get_cell_meridional_size


   SUBROUTINE nemo_get_cell_depth(array_out) BIND(C, name='nemo_get_cell_depth')
      REAL(c_double), INTENT(out) :: array_out(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1, jpk)
      CALL copy_3d_to_c(gdept_0, array_out)
   END SUBROUTINE nemo_get_cell_depth


   SUBROUTINE nemo_get_bottom_level_index(array_out) BIND(C, name='nemo_get_bottom_level_index')
      INTEGER(c_int), INTENT(out) :: array_out(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1)
      CALL copy_int_2d_to_c(mbkt, array_out)
   END SUBROUTINE nemo_get_bottom_level_index

END MODULE nemo_julia_wrapper
