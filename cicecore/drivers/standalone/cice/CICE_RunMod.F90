!=======================================================================
!
!  Main driver for time stepping of CICE.
!
!  authors Elizabeth C. Hunke, LANL
!          Philip W. Jones, LANL
!          William H. Lipscomb, LANL
!
! 2006 ECH: moved exit timeLoop to prevent execution of unnecessary timestep
! 2006 ECH: Streamlined for efficiency
! 2006 ECH: Converted to free source form (F90)
! 2007 BPB: Modified Delta-Eddington shortwave interface
! 2008 ECH: moved ESMF code to its own driver

      module CICE_RunMod

      use ice_kinds_mod
      use ice_communicate, only: my_task, master_task
      use ice_fileunits, only: nu_diag
      use ice_arrays_column, only: oceanmixed_ice
      use ice_constants, only: c0, c1
      use ice_constants, only: field_loc_center, field_type_scalar
      use ice_exit, only: abort_ice
      use ice_memusage, only: ice_memusage_print
      use icepack_intfc, only: icepack_warnings_flush, icepack_warnings_aborted
      use icepack_intfc, only: icepack_max_iso, icepack_max_aero
      use icepack_intfc, only: icepack_query_parameters
      use icepack_intfc, only: icepack_query_tracer_flags, icepack_query_tracer_sizes

      implicit none
      private
      public :: CICE_Run, ice_step

!=======================================================================

      contains

!=======================================================================
!
!  This is the main driver routine for advancing CICE forward in time.
!
!  author Elizabeth C. Hunke, LANL
!         Philip W. Jones, LANL
!         William H. Lipscomb, LANL

      subroutine CICE_Run

      use ice_calendar, only: dt, stop_now, advance_timestep
      use ice_forcing, only: get_forcing_atmo, get_forcing_ocn, &
          get_wave_spec
      use ice_forcing_bgc, only: get_forcing_bgc, get_atm_bgc, &
          fiso_default, faero_default
      use ice_flux, only: init_flux_atm, init_flux_ocn
      use ice_timers, only: ice_timer_start, ice_timer_stop, &
          timer_couple, timer_step
      logical (kind=log_kind) :: &
          tr_iso, tr_aero, tr_zaero, skl_bgc, z_tracers, wave_spec, tr_fsd
      character(len=*), parameter :: subname = '(CICE_Run)'

   !--------------------------------------------------------------------
   !  initialize error code and step timer
   !--------------------------------------------------------------------

      call ice_timer_start(timer_step)   ! start timing entire run

      call icepack_query_parameters(skl_bgc_out=skl_bgc, &
                                    z_tracers_out=z_tracers, &
                                    wave_spec_out=wave_spec)
      call icepack_query_tracer_flags(tr_iso_out=tr_iso, &
                                      tr_aero_out=tr_aero, &
                                      tr_zaero_out=tr_zaero, &
                                      tr_fsd_out=tr_fsd)
      call icepack_warnings_flush(nu_diag)
      if (icepack_warnings_aborted()) call abort_ice(error_message=subname, &
         file=__FILE__, line=__LINE__)

#ifndef CICE_IN_NEMO
   !--------------------------------------------------------------------
   ! timestep loop
   !--------------------------------------------------------------------

      timeLoop: do
#endif

         call ice_step

! tcraig, use advance_timestep now
!         istep  = istep  + 1    ! update time step counters
!         istep1 = istep1 + 1
!         time = time + dt       ! determine the time and date
!         call calendar(time)    ! at the end of the timestep
         call advance_timestep()     ! advance time

#ifndef CICE_IN_NEMO
         if (stop_now >= 1) exit timeLoop
#endif

         call ice_timer_start(timer_couple)  ! atm/ocn coupling

! for now, wave_spectrum is constant in time
!         if (tr_fsd .and. wave_spec) call get_wave_spec ! wave spectrum in ice
         call get_forcing_atmo     ! atmospheric forcing from data
         call get_forcing_ocn(dt)  ! ocean forcing from data

         ! isotopes
         if (tr_iso)     call fiso_default                 ! default values
         ! aerosols
         ! if (tr_aero)  call faero_data                   ! data file
         ! if (tr_zaero) call fzaero_data                  ! data file (gx1)
         if (tr_aero .or. tr_zaero)  call faero_default    ! default values

         if (skl_bgc .or. z_tracers) call get_forcing_bgc  ! biogeochemistry
         if (z_tracers) call get_atm_bgc                   ! biogeochemistry

         call init_flux_atm  ! Initialize atmosphere fluxes sent to coupler
         call init_flux_ocn  ! initialize ocean fluxes sent to coupler

         call ice_timer_stop(timer_couple)    ! atm/ocn coupling

#ifndef CICE_IN_NEMO
      enddo timeLoop
#endif

   !--------------------------------------------------------------------
   ! end of timestep loop
   !--------------------------------------------------------------------

      call ice_timer_stop(timer_step)   ! end timestepping loop timer

      end subroutine CICE_Run

!=======================================================================
!
!  Calls drivers for physics components, some initialization, and output
!
!  author Elizabeth C. Hunke, LANL
!         William H. Lipscomb, LANL

      subroutine ice_step

      use ice_boundary, only: ice_HaloUpdate
      use ice_calendar, only: dt, dt_dyn, ndtd, diagfreq, write_restart, istep
      use ice_diagnostics, only: init_mass_diags, runtime_diags, debug_model, debug_ice
      use ice_diagnostics_bgc, only: hbrine_diags, bgc_diags
      use ice_domain, only: halo_info, nblocks
      use ice_dyn_eap, only: write_restart_eap
      use ice_dyn_shared, only: kdyn, kridge
      use ice_flux, only: scale_factor, init_history_therm, &
          daidtt, daidtd, dvidtt, dvidtd, dvsdtt, dvsdtd, dagedtt, dagedtd
      use ice_history, only: accum_hist
      use ice_history_bgc, only: init_history_bgc
      use ice_restart, only: final_restart
      use ice_restart_column, only: write_restart_age, write_restart_FY, &
          write_restart_lvl, write_restart_pond_lvl, write_restart_pond_sealvl,&
          write_restart_pond_topo, write_restart_aero, write_restart_fsd, &
          write_restart_iso, write_restart_bgc, write_restart_hbrine, &
          write_restart_snow
      use ice_restart_driver, only: dumpfile
      use ice_restoring, only: restore_ice, ice_HaloRestore
      use ice_step_mod, only: prep_radiation, step_therm1, step_therm2, &
          update_state, step_dyn_horiz, step_dyn_ridge, step_radiation, &
          biogeochemistry, step_prep, step_dyn_wave, step_snow
      use ice_timers, only: ice_timer_start, ice_timer_stop, &
          timer_diags, timer_column, timer_thermo, timer_bound, &
          timer_hist, timer_readwrite

      integer (kind=int_kind) :: &
         iblk        , & ! block index
         k           , & ! dynamics supercycling index
         ktherm          ! thermodynamics is off when ktherm = -1

      real (kind=dbl_kind) :: &
         offset          ! d(age)/dt time offset

      logical (kind=log_kind) :: &
          tr_iage, tr_FY, tr_lvl, tr_fsd, tr_snow, &
          tr_pond_lvl, tr_pond_sealvl, tr_pond_topo, &
          tr_brine, tr_iso, tr_aero, &
          calc_Tsfc, skl_bgc, z_tracers, wave_spec

      character(len=*), parameter :: subname = '(ice_step)'

      character (len=char_len) :: plabeld

      if (debug_model) then
         plabeld = 'beginning time step'
         do iblk = 1, nblocks
            call debug_ice (iblk, plabeld)
         enddo
      endif

      call icepack_query_parameters(calc_Tsfc_out=calc_Tsfc, skl_bgc_out=skl_bgc, &
           z_tracers_out=z_tracers, ktherm_out=ktherm, wave_spec_out=wave_spec)
      call icepack_query_tracer_flags(tr_iage_out=tr_iage, tr_FY_out=tr_FY, &
           tr_lvl_out=tr_lvl, tr_pond_lvl_out=tr_pond_lvl, tr_pond_sealvl_out=tr_pond_sealvl, &
           tr_pond_topo_out=tr_pond_topo, tr_brine_out=tr_brine, tr_aero_out=tr_aero, &
           tr_iso_out=tr_iso, tr_fsd_out=tr_fsd, tr_snow_out=tr_snow)
      call icepack_warnings_flush(nu_diag)
      if (icepack_warnings_aborted()) call abort_ice(error_message=subname, &
         file=__FILE__, line=__LINE__)

      !-----------------------------------------------------------------
      ! restoring on grid boundaries
      !-----------------------------------------------------------------

         if (restore_ice) call ice_HaloRestore

      !-----------------------------------------------------------------
      ! initialize diagnostics and save initial state values
      !-----------------------------------------------------------------

         call ice_timer_start(timer_diags)  ! diagnostics/history
         call init_mass_diags   ! diagnostics per timestep
         call init_history_therm
         call init_history_bgc
         call ice_timer_stop(timer_diags)   ! diagnostics/history

         call ice_timer_start(timer_column)  ! column physics
         call ice_timer_start(timer_thermo)  ! thermodynamics

         call step_prep

         if (ktherm >= 0) then
            !$OMP PARALLEL DO PRIVATE(iblk) SCHEDULE(runtime)
            do iblk = 1, nblocks

      !-----------------------------------------------------------------
      ! scale radiation fields
      !-----------------------------------------------------------------

               if (calc_Tsfc) call prep_radiation (iblk)

               if (debug_model) then
                  plabeld = 'post prep_radiation'
                  call debug_ice (iblk, plabeld)
               endif

      !-----------------------------------------------------------------
      ! thermodynamics and biogeochemistry
      !-----------------------------------------------------------------

               call step_therm1     (dt, iblk) ! vertical thermodynamics

               if (debug_model) then
                  plabeld = 'post step_therm1'
                  call debug_ice (iblk, plabeld)
               endif

               call biogeochemistry (dt, iblk) ! biogeochemistry

               if (debug_model) then
                  plabeld = 'post biogeochemistry'
                  call debug_ice (iblk, plabeld)
               endif

               call step_therm2     (dt, iblk) ! ice thickness distribution thermo

               if (debug_model) then
                  plabeld = 'post step_therm2'
                  call debug_ice (iblk, plabeld)
               endif

            enddo
            !$OMP END PARALLEL DO
         endif ! ktherm > 0

         ! clean up, update tendency diagnostics
         offset = dt
         call update_state (dt=dt, daidt=daidtt, dvidt=dvidtt, dvsdt=dvsdtt, &
                            dagedt=dagedtt, offset=offset)

         call ice_timer_stop(timer_thermo) ! thermodynamics
         call ice_timer_stop(timer_column) ! column physics

      !-----------------------------------------------------------------
      ! dynamics, transport, ridging
      !-----------------------------------------------------------------

         ! wave fracture of the floe size distribution
         ! note this is called outside of the dynamics subcycling loop
         if (tr_fsd .and. wave_spec) call step_dyn_wave(dt)

         do k = 1, ndtd

            ! momentum, stress, transport
            call step_dyn_horiz (dt_dyn)

            if (debug_model) then
               plabeld = 'post step_dyn_horiz'
               do iblk = 1, nblocks
                  call debug_ice (iblk, plabeld)
               enddo ! iblk
            endif

            ! ridging
            !$OMP PARALLEL DO PRIVATE(iblk) SCHEDULE(runtime)
            do iblk = 1, nblocks
               if (kridge > 0) call step_dyn_ridge (dt_dyn, ndtd, iblk)
            enddo
            !$OMP END PARALLEL DO

            if (debug_model) then
               plabeld = 'post step_dyn_ridge'
               do iblk = 1, nblocks
                  call debug_ice (iblk, plabeld)
               enddo ! iblk
            endif

            ! clean up, update tendency diagnostics
            offset = c0
            call update_state (dt=dt_dyn, daidt=daidtd, dvidt=dvidtd, dvsdt=dvsdtd, &
                               dagedt=dagedtd, offset=offset)

         enddo

         if (debug_model) then
            plabeld = 'post dynamics'
            do iblk = 1, nblocks
               call debug_ice (iblk, plabeld)
            enddo
         endif

         call ice_timer_start(timer_column)  ! column physics
         call ice_timer_start(timer_thermo)  ! thermodynamics

      !-----------------------------------------------------------------
      ! snow redistribution and metamorphosis
      !-----------------------------------------------------------------

         if (tr_snow) then         ! advanced snow physics
            !$OMP PARALLEL DO PRIVATE(iblk) SCHEDULE(runtime)
            do iblk = 1, nblocks
               call step_snow (dt, iblk)
            enddo
            !$OMP END PARALLEL DO
            call update_state (dt=dt) ! clean up
         endif

         !$OMP PARALLEL DO PRIVATE(iblk) SCHEDULE(runtime)
         do iblk = 1, nblocks

      !-----------------------------------------------------------------
      ! albedo, shortwave radiation
      !-----------------------------------------------------------------

            if (ktherm >= 0) call step_radiation (dt, iblk)

            if (debug_model) then
               plabeld = 'post step_radiation'
               call debug_ice (iblk, plabeld)
            endif

      !-----------------------------------------------------------------
      ! get ready for coupling and the next time step
      !-----------------------------------------------------------------

            call coupling_prep (iblk)

            if (debug_model) then
               plabeld = 'post coupling_prep'
               call debug_ice (iblk, plabeld)
            endif

         enddo ! iblk
         !$OMP END PARALLEL DO

         call ice_timer_start(timer_bound)
         call ice_HaloUpdate (scale_factor,     halo_info, &
                              field_loc_center, field_type_scalar)
         call ice_timer_stop(timer_bound)

         call ice_timer_stop(timer_thermo) ! thermodynamics
         call ice_timer_stop(timer_column) ! column physics

      !-----------------------------------------------------------------
      ! write data
      !-----------------------------------------------------------------

         call ice_timer_start(timer_diags)  ! diagnostics
         if (mod(istep,diagfreq) == 0) then
            call runtime_diags(dt)          ! log file
            if (skl_bgc .or. z_tracers)  call bgc_diags
            if (tr_brine) call hbrine_diags
            if (my_task == master_task) then
               call ice_memusage_print(nu_diag,subname)
            endif
         endif
         call ice_timer_stop(timer_diags)   ! diagnostics

         call ice_timer_start(timer_hist)   ! history
         call accum_hist (dt)               ! history file
         call ice_timer_stop(timer_hist)    ! history

         call ice_timer_start(timer_readwrite)  ! reading/writing
         if (write_restart == 1) then
            call dumpfile     ! core variables for restarting
            if (tr_iage)      call write_restart_age
            if (tr_FY)        call write_restart_FY
            if (tr_lvl)       call write_restart_lvl
            if (tr_pond_lvl)  call write_restart_pond_lvl
            if (tr_pond_sealvl)  call write_restart_pond_sealvl
            if (tr_pond_topo) call write_restart_pond_topo
            if (tr_snow)      call write_restart_snow
            if (tr_fsd)       call write_restart_fsd
            if (tr_iso)       call write_restart_iso
            if (tr_aero)      call write_restart_aero
            if (skl_bgc .or. z_tracers) &
                              call write_restart_bgc
            if (tr_brine)     call write_restart_hbrine
            if (kdyn == 2)    call write_restart_eap
            call final_restart
         endif
         call ice_timer_stop(timer_readwrite)  ! reading/writing

      end subroutine ice_step

!=======================================================================
!
! Prepare for coupling
!
! authors: Elizabeth C. Hunke, LANL

      subroutine coupling_prep (iblk)

      use ice_arrays_column, only: alvdfn, alidfn, alvdrn, alidrn, &
          albicen, albsnon, albpndn, apeffn, snowfracn
      use ice_blocks, only: nx_block, ny_block, get_block, block
      use ice_domain, only: blocks_ice
      use ice_calendar, only: dt, nstreams
      use ice_domain_size, only: ncat
      use ice_flux, only: alvdf, alidf, alvdr, alidr, albice, albsno, &
          albpnd, albcnt, apeff_ai, fpond, fresh, l_mpond_fresh, &
          alvdf_ai, alidf_ai, alvdr_ai, alidr_ai, fhocn_ai, &
          fresh_ai, fsalt_ai, fsalt, &
          fswthru_ai, fhocn, scale_factor, snowfrac, &
          fswthru, fswthru_vdr, fswthru_vdf, fswthru_idr, fswthru_idf, &
          swvdr, swidr, swvdf, swidf, Tf, Tair, Qa, strairxT, strairyT, &
          fsens, flat, fswabs, flwout, evap, Tref, Qref, &
          scale_fluxes, frzmlt_init, frzmlt
      use ice_flux_bgc, only: faero_ocn, fiso_ocn, Qref_iso, fiso_evap, &
          flux_bio, flux_bio_ai
      use ice_grid, only: tmask
      use ice_state, only: aicen, aice
#ifdef CICE_IN_NEMO
      use ice_state, only: aice_init
      use ice_flux, only: flatn_f, fsurfn_f
#endif
      use ice_step_mod, only: ocean_mixed_layer
      use ice_timers, only: timer_couple, ice_timer_start, ice_timer_stop

      integer (kind=int_kind), intent(in) :: &
         iblk            ! block index

      ! local variables

      integer (kind=int_kind) :: &
         ilo,ihi,jlo,jhi, & ! beginning and end of physical domain
         n           , & ! thickness category index
         i,j         , & ! horizontal indices
         k           , & ! tracer index
         nbtrcr          !

      type (block) :: &
         this_block         ! block information for current block

      logical (kind=log_kind) :: &
         calc_Tsfc       !

      real (kind=dbl_kind) :: &
         cszn        , & ! counter for history averaging
         puny        , & !
         rhofresh    , & !
         netsw           ! flag for shortwave radiation presence

      character(len=*), parameter :: subname = '(coupling_prep)'

         call icepack_query_parameters(puny_out=puny, rhofresh_out=rhofresh)
         call icepack_query_tracer_sizes(nbtrcr_out=nbtrcr)
         call icepack_query_parameters(calc_Tsfc_out=calc_Tsfc)
         call icepack_warnings_flush(nu_diag)
         if (icepack_warnings_aborted()) call abort_ice(error_message=subname, &
            file=__FILE__, line=__LINE__)

      !-----------------------------------------------------------------
      ! Save current value of frzmlt for diagnostics.
      ! Update mixed layer with heat and radiation from ice.
      !-----------------------------------------------------------------

         do j = 1, ny_block
         do i = 1, nx_block
            frzmlt_init  (i,j,iblk) = frzmlt(i,j,iblk)
         enddo
         enddo

         call ice_timer_start(timer_couple,iblk)   ! atm/ocn coupling

         if (oceanmixed_ice) &
         call ocean_mixed_layer (dt,iblk) ! ocean surface fluxes and sst

      !-----------------------------------------------------------------
      ! Aggregate albedos
      !-----------------------------------------------------------------

         do j = 1, ny_block
         do i = 1, nx_block
            alvdf(i,j,iblk) = c0
            alidf(i,j,iblk) = c0
            alvdr(i,j,iblk) = c0
            alidr(i,j,iblk) = c0

            albice(i,j,iblk) = c0
            albsno(i,j,iblk) = c0
            albpnd(i,j,iblk) = c0
            apeff_ai(i,j,iblk) = c0
            snowfrac(i,j,iblk) = c0

            ! for history averaging
            cszn = c0
            netsw = swvdr(i,j,iblk)+swidr(i,j,iblk)+swvdf(i,j,iblk)+swidf(i,j,iblk)
            if (netsw > puny) cszn = c1
            do n = 1, nstreams
               albcnt(i,j,iblk,n) = albcnt(i,j,iblk,n) + cszn
            enddo
         enddo
         enddo

         this_block = get_block(blocks_ice(iblk),iblk)
         ilo = this_block%ilo
         ihi = this_block%ihi
         jlo = this_block%jlo
         jhi = this_block%jhi

         do n = 1, ncat
         do j = jlo, jhi
         do i = ilo, ihi
            if (aicen(i,j,n,iblk) > puny) then

            alvdf(i,j,iblk) = alvdf(i,j,iblk) &
               + alvdfn(i,j,n,iblk)*aicen(i,j,n,iblk)
            alidf(i,j,iblk) = alidf(i,j,iblk) &
               + alidfn(i,j,n,iblk)*aicen(i,j,n,iblk)
            alvdr(i,j,iblk) = alvdr(i,j,iblk) &
               + alvdrn(i,j,n,iblk)*aicen(i,j,n,iblk)
            alidr(i,j,iblk) = alidr(i,j,iblk) &
               + alidrn(i,j,n,iblk)*aicen(i,j,n,iblk)

            netsw = swvdr(i,j,iblk) + swidr(i,j,iblk) &
                  + swvdf(i,j,iblk) + swidf(i,j,iblk)
            if (netsw > puny) then ! sun above horizon
            albice(i,j,iblk) = albice(i,j,iblk) &
               + albicen(i,j,n,iblk)*aicen(i,j,n,iblk)
            albsno(i,j,iblk) = albsno(i,j,iblk) &
               + albsnon(i,j,n,iblk)*aicen(i,j,n,iblk)
            albpnd(i,j,iblk) = albpnd(i,j,iblk) &
               + albpndn(i,j,n,iblk)*aicen(i,j,n,iblk)
            endif

            apeff_ai(i,j,iblk) = apeff_ai(i,j,iblk) &       ! for history
               + apeffn(i,j,n,iblk)*aicen(i,j,n,iblk)
            snowfrac(i,j,iblk) = snowfrac(i,j,iblk) &       ! for history
               + snowfracn(i,j,n,iblk)*aicen(i,j,n,iblk)

            endif ! aicen > puny
         enddo
         enddo
         enddo

         do j = 1, ny_block
         do i = 1, nx_block

      !-----------------------------------------------------------------
      ! reduce fresh by fpond for coupling
      !-----------------------------------------------------------------

            if (l_mpond_fresh) then
               fpond(i,j,iblk) = fpond(i,j,iblk) * rhofresh/dt
               fresh(i,j,iblk) = fresh(i,j,iblk) - fpond(i,j,iblk)
            endif

      !----------------------------------------------------------------
      ! Store grid box mean albedos and fluxes before scaling by aice
      !----------------------------------------------------------------

            alvdf_ai  (i,j,iblk) = alvdf  (i,j,iblk)
            alidf_ai  (i,j,iblk) = alidf  (i,j,iblk)
            alvdr_ai  (i,j,iblk) = alvdr  (i,j,iblk)
            alidr_ai  (i,j,iblk) = alidr  (i,j,iblk)
            fresh_ai  (i,j,iblk) = fresh  (i,j,iblk)
            fsalt_ai  (i,j,iblk) = fsalt  (i,j,iblk)
            fhocn_ai  (i,j,iblk) = fhocn  (i,j,iblk)
            fswthru_ai(i,j,iblk) = fswthru(i,j,iblk)

            if (nbtrcr > 0) then
            do k = 1, nbtrcr
              flux_bio_ai  (i,j,k,iblk) = flux_bio  (i,j,k,iblk)
            enddo
            endif

      !-----------------------------------------------------------------
      ! Save net shortwave for scaling factor in scale_factor
      !-----------------------------------------------------------------
            scale_factor(i,j,iblk) = &
                       swvdr(i,j,iblk)*(c1 - alvdr_ai(i,j,iblk)) &
                     + swvdf(i,j,iblk)*(c1 - alvdf_ai(i,j,iblk)) &
                     + swidr(i,j,iblk)*(c1 - alidr_ai(i,j,iblk)) &
                     + swidf(i,j,iblk)*(c1 - alidf_ai(i,j,iblk))

         enddo
         enddo

      !-----------------------------------------------------------------
      ! Divide fluxes by ice area
      !  - the CESM coupler assumes fluxes are per unit ice area
      !  - also needed for global budget in diagnostics
      !-----------------------------------------------------------------

         call scale_fluxes (nx_block,            ny_block,           &
                            tmask    (:,:,iblk), nbtrcr,             &
                            icepack_max_aero,                        &
                            aice     (:,:,iblk), Tf      (:,:,iblk), &
                            Tair     (:,:,iblk), Qa      (:,:,iblk), &
                            strairxT (:,:,iblk), strairyT(:,:,iblk), &
                            fsens    (:,:,iblk), flat    (:,:,iblk), &
                            fswabs   (:,:,iblk), flwout  (:,:,iblk), &
                            evap     (:,:,iblk),                     &
                            Tref     (:,:,iblk), Qref    (:,:,iblk), &
                            fresh    (:,:,iblk), fsalt   (:,:,iblk), &
                            fhocn    (:,:,iblk),                     &
                            fswthru  (:,:,iblk),                     &
                            fswthru_vdr (:,:,iblk),                  &
                            fswthru_vdf (:,:,iblk),                  &
                            fswthru_idr (:,:,iblk),                  &
                            fswthru_idf (:,:,iblk),                  &
                            faero_ocn(:,:,:,iblk),                   &
                            alvdr    (:,:,iblk), alidr   (:,:,iblk), &
                            alvdf    (:,:,iblk), alidf   (:,:,iblk), &
                            flux_bio =flux_bio (:,:,1:nbtrcr,iblk),  &
                            Qref_iso =Qref_iso (:,:,:,iblk),         &
                            fiso_evap=fiso_evap(:,:,:,iblk),         &
                            fiso_ocn =fiso_ocn (:,:,:,iblk))

#ifdef CICE_IN_NEMO
!echmod - comment this out for efficiency, if .not. calc_Tsfc
         if (.not. calc_Tsfc) then

       !---------------------------------------------------------------
       ! If surface fluxes were provided, conserve these fluxes at ice
       ! free points by passing to ocean.
       !---------------------------------------------------------------

            call sfcflux_to_ocn &
                         (nx_block,              ny_block,             &
                          tmask   (:,:,iblk),    aice_init(:,:,iblk),  &
                          fsurfn_f (:,:,:,iblk), flatn_f(:,:,:,iblk),  &
                          fresh    (:,:,iblk),   fhocn    (:,:,iblk))
         endif
!echmod
#endif
         call ice_timer_stop(timer_couple,iblk)   ! atm/ocn coupling

      end subroutine coupling_prep

#ifdef CICE_IN_NEMO

!=======================================================================
!
! If surface heat fluxes are provided to CICE instead of CICE calculating
! them internally (i.e. .not. calc_Tsfc), then these heat fluxes can
! be provided at points which do not have ice.  (This is could be due to
! the heat fluxes being calculated on a lower resolution grid or the
! heat fluxes not recalculated at every CICE timestep.)  At ice free points,
! conserve energy and water by passing these fluxes to the ocean.
!
! author: A. McLaren, Met Office

      subroutine sfcflux_to_ocn(nx_block,   ny_block,     &
                                tmask,      aice,         &
                                fsurfn_f,   flatn_f,      &
                                fresh,      fhocn)

      use ice_domain_size, only: ncat

      integer (kind=int_kind), intent(in) :: &
          nx_block, ny_block  ! block dimensions

      logical (kind=log_kind), dimension (nx_block,ny_block), intent(in) :: &
          tmask       ! land/boundary mask, thickness (T-cell)

      real (kind=dbl_kind), dimension(nx_block,ny_block), intent(in):: &
          aice        ! initial ice concentration

      real (kind=dbl_kind), dimension(nx_block,ny_block,ncat), intent(in) :: &
          fsurfn_f, & ! net surface heat flux (provided as forcing)
          flatn_f     ! latent heat flux (provided as forcing)

      real (kind=dbl_kind), dimension(nx_block,ny_block), intent(inout):: &
          fresh        , & ! fresh water flux to ocean         (kg/m2/s)
          fhocn            ! actual ocn/ice heat flx           (W/m**2)


      ! local variables
      integer (kind=int_kind) :: &
          i, j, n    ! horizontal indices

      real (kind=dbl_kind)    :: &
          puny, &          !
          Lsub, &          !
          rLsub            ! 1/Lsub

      character(len=*), parameter :: subname = '(sfcflux_to_ocn)'

      call icepack_query_parameters(puny_out=puny, Lsub_out=Lsub)
      call icepack_warnings_flush(nu_diag)
      if (icepack_warnings_aborted()) call abort_ice(error_message=subname, &
         file=__FILE__, line=__LINE__)
      rLsub = c1 / Lsub

      do n = 1, ncat
         do j = 1, ny_block
         do i = 1, nx_block
            if (tmask(i,j) .and. aice(i,j) <= puny) then
               fhocn(i,j)      = fhocn(i,j)              &
                            + fsurfn_f(i,j,n) + flatn_f(i,j,n)
               fresh(i,j)      = fresh(i,j)              &
                                 + flatn_f(i,j,n) * rLsub
            endif
         enddo   ! i
         enddo   ! j
      enddo      ! n


      end subroutine sfcflux_to_ocn

#endif

!=======================================================================

      end module CICE_RunMod

!=======================================================================
