/*
All ShuttleMove procs go here
*/

/************************************Base procs************************************/

// Called on every turf in the shuttle region, returns a bitflag for allowed movements of that turf
// returns the new move_mode (based on the old)
/turf/proc/fromShuttleMove(turf/newT, move_mode)
	if(!(move_mode & MOVE_AREA) || !isshuttleturf(src))
		return move_mode

	return move_mode | MOVE_TURF | MOVE_CONTENTS

// Called from the new turf before anything has been moved
// Only gets called if fromShuttleMove returns true first
// returns the new move_mode (based on the old)
/turf/proc/toShuttleMove(turf/oldT, move_mode, obj/docking_port/mobile/shuttle)
	. = move_mode
	if(!(. & MOVE_TURF))
		return

	var/shuttle_dir = shuttle.dir
	for(var/i in contents)
		var/atom/movable/thing = i
		if(ismob(thing))
			if(isliving(thing))
				var/mob/living/M = thing
				if(M.buckled)
					M.buckled.unbuckle_mob(M, 1)
				if(M.pulledby)
					M.pulledby.stop_pulling()
				M.stop_pulling()
				M.visible_message(span_warning("[shuttle] slams into [M]!"))
				SSblackbox.record_feedback("tally", "shuttle_gib", 1, M.type)
				log_shuttle("[key_name(M)] was shuttle gibbed by [shuttle].")
				M.investigate_log("has been gibbed by [shuttle].", INVESTIGATE_DEATHS)
				M.gib(DROP_ALL_REMAINS)


		else //non-living mobs shouldn't be affected by shuttles, which is why this is an else
			if(istype(thing, /obj/effect/abstract) || istype(thing, /obj/singularity) || istype(thing, /obj/energy_ball))
				continue
			if(!thing.anchored)
				step(thing, shuttle_dir)
			else
				qdel(thing)

// Called on the old turf to move the turf data
/turf/proc/onShuttleMove(turf/newT, list/movement_force, move_dir)
	if(newT == src) // In case of in place shuttle rotation shenanigans.
		return
	// Destination turf changes.
	// Baseturfs is definitely a list or this proc wouldnt be called.
	var/shuttle_depth = depth_to_find_baseturf(/turf/baseturf_skipover/shuttle)

	if(!shuttle_depth)
		CRASH("A turf queued to move via shuttle somehow had no skipover in baseturfs. [src]([type]):[loc]")
	newT.CopyOnTop(src, 1, shuttle_depth, TRUE)
	newT.blocks_air = TRUE
	newT.air_update_turf(TRUE, FALSE)
	blocks_air = TRUE
	air_update_turf(TRUE, TRUE)
	if(isopenturf(newT))
		var/turf/open/new_open = newT
		new_open.copy_air_with_tile(src)
	SEND_SIGNAL(src, COMSIG_TURF_ON_SHUTTLE_MOVE, newT)

	return TRUE

// Called on the new turf after everything has been moved
/turf/proc/afterShuttleMove(turf/oldT, rotation)
	//Dealing with the turf we left behind
	oldT.TransferComponents(src)

	SSexplosions.wipe_turf(src)
	var/shuttle_depth = depth_to_find_baseturf(/turf/baseturf_skipover/shuttle)

	if(shuttle_depth)
		oldT.ScrapeAway(shuttle_depth)

	if(rotation)
		shuttleRotate(rotation) //see shuttle_rotate.dm

	return TRUE

/turf/proc/lateShuttleMove(turf/oldT)
	blocks_air = initial(blocks_air)
	air_update_turf(TRUE, blocks_air)
	oldT.blocks_air = initial(oldT.blocks_air)
	oldT.air_update_turf(TRUE, oldT.blocks_air)


/////////////////////////////////////////////////////////////////////////////////////

// Called on every atom in shuttle turf contents before anything has been moved
// returns the new move_mode (based on the old)
// WARNING: Do not leave turf contents in beforeShuttleMove or dock() will runtime
/atom/movable/proc/beforeShuttleMove(turf/newT, rotation, move_mode, obj/docking_port/mobile/moving_dock)
	return move_mode

/// Called on atoms to move the atom to the new location
/atom/movable/proc/onShuttleMove(turf/newT, turf/oldT, list/movement_force, move_dir, obj/docking_port/stationary/old_dock, obj/docking_port/mobile/moving_dock)
	if(newT == oldT) // In case of in place shuttle rotation shenanigans.
		return

	if(loc != oldT) // This is for multi tile objects
		return

	abstract_move(newT)

	return TRUE

// Called on atoms after everything has been moved
/atom/movable/proc/afterShuttleMove(turf/oldT, list/movement_force, shuttle_dir, shuttle_preferred_direction, move_dir, rotation)
	SEND_SIGNAL(src, COMSIG_ATOM_AFTER_SHUTTLE_MOVE, oldT)
	if(light)
		update_light()
	if(rotation)
		shuttleRotate(rotation)

	update_parallax_contents()

	return TRUE

/atom/movable/proc/lateShuttleMove(turf/oldT, list/movement_force, move_dir)
	if(!movement_force || anchored)
		return
	var/throw_force = movement_force["THROW"]
	if(!throw_force)
		return
	var/turf/target = get_edge_target_turf(src, move_dir)
	var/range = throw_force * 10
	range = CEILING(rand(range-(range*0.1), range+(range*0.1)), 10)/10
	var/speed = range/5
	safe_throw_at(target, range, speed, force = MOVE_FORCE_EXTREMELY_STRONG)

/////////////////////////////////////////////////////////////////////////////////////

// Called on areas before anything has been moved
// returns the new move_mode (based on the old)
/area/proc/beforeShuttleMove(list/shuttle_areas)
	if(!shuttle_areas[src])
		return NONE
	return MOVE_AREA

// Called on areas to move their turf between areas
/area/proc/onShuttleMove(turf/oldT, turf/newT, area/underlying_old_area)
	if(newT == oldT) // In case of in place shuttle rotation shenanigans.
		return TRUE

	oldT.change_area(src, underlying_old_area)
	//The old turf has now been given back to the area that turf originaly belonged to

	var/area/old_dest_area = newT.loc
	parallax_movedir = old_dest_area.parallax_movedir
	newT.change_area(old_dest_area, src)
	return TRUE

// Called on areas after everything has been moved
/area/proc/afterShuttleMove(new_parallax_dir)
	parallax_movedir = new_parallax_dir
	return TRUE

/area/proc/lateShuttleMove()
	return

/************************************Turf move procs************************************/

/************************************Area move procs************************************/

/************************************Machinery move procs************************************/

/obj/machinery/door/airlock/beforeShuttleMove(turf/newT, rotation, move_mode, obj/docking_port/mobile/moving_dock)
	. = ..()
	for(var/obj/machinery/door/airlock/other_airlock in range(2, src))  // includes src, extended because some escape pods have 1 plating turf exposed to space
		other_airlock.shuttledocked = FALSE
		other_airlock.air_tight = TRUE
		INVOKE_ASYNC(other_airlock, TYPE_PROC_REF(/obj/machinery/door/, close), FALSE, TRUE) // force crush

/obj/machinery/door/airlock/afterShuttleMove(turf/oldT, list/movement_force, shuttle_dir, shuttle_preferred_direction, move_dir, rotation)
	. = ..()
	var/current_area = get_area(src)
	for(var/obj/machinery/door/airlock/other_airlock in orange(2, src))  // does not include src, extended because some escape pods have 1 plating turf exposed to space
		if(get_area(other_airlock) != current_area)  // does not include double-wide airlocks unless actually docked
			// Cycle linking is only disabled if we are actually adjacent to another airlock
			shuttledocked = TRUE
			other_airlock.shuttledocked = TRUE

/obj/machinery/camera/beforeShuttleMove(turf/newT, rotation, move_mode, obj/docking_port/mobile/moving_dock)
	. = ..()
	if(. & MOVE_AREA)
		. |= MOVE_CONTENTS
		GLOB.cameranet.removeCamera(src)

/obj/machinery/camera/afterShuttleMove(turf/oldT, list/movement_force, shuttle_dir, shuttle_preferred_direction, move_dir, rotation)
	. = ..()
	GLOB.cameranet.addCamera(src)

/obj/machinery/mech_bay_recharge_port/afterShuttleMove(turf/oldT, list/movement_force, shuttle_dir, shuttle_preferred_direction, move_dir)
	. = ..()
	recharging_turf = get_step(loc, dir)

/obj/machinery/atmospherics/afterShuttleMove(turf/oldT, list/movement_force, shuttle_dir, shuttle_preferred_direction, move_dir, rotation)
	. = ..()
	if(pipe_vision_img)
		pipe_vision_img.loc = loc

/obj/machinery/computer/auxiliary_base/afterShuttleMove(turf/oldT, list/movement_force, shuttle_dir, shuttle_preferred_direction, move_dir, rotation)
	. = ..()
	if(is_mining_level(z)) //Avoids double logging and landing on other Z-levels due to badminnery
		SSblackbox.record_feedback("associative", "colonies_dropped", 1, list("x" = x, "y" = y, "z" = z))

/obj/machinery/atmospherics/afterShuttleMove(turf/oldT, list/movement_force, shuttle_dir, shuttle_preferred_direction, move_dir, rotation)
	. = ..()
	var/missing_nodes = FALSE
	for(var/i in 1 to device_type)
		if(nodes[i])
			var/obj/machinery/atmospherics/node = nodes[i]
			var/connected = FALSE
			for(var/D in GLOB.cardinals)
				if(node in get_step(src, D))
					connected = TRUE
					break

			if(!connected)
				nullify_node(i)

		if(!nodes[i])
			missing_nodes = TRUE

	if(missing_nodes)
		atmos_init()
		for(var/obj/machinery/atmospherics/A in pipeline_expansion())
			A.atmos_init()
			if(A.return_pipenet())
				A.add_member(src)
		SSair.add_to_rebuild_queue(src)
	else
		// atmos_init() calls update_appearance(), so we don't need to call it
		update_appearance()

/obj/machinery/navbeacon/beforeShuttleMove(turf/newT, rotation, move_mode, obj/docking_port/mobile/moving_dock)
	. = ..()
	GLOB.navbeacons["[z]"] -= src
	GLOB.deliverybeacons -= src

/obj/machinery/navbeacon/afterShuttleMove(turf/oldT, list/movement_force, shuttle_dir, shuttle_preferred_direction, move_dir, rotation)
	. = ..()

	if(codes[NAVBEACON_PATROL_MODE])
		if(!GLOB.navbeacons["[z]"])
			GLOB.navbeacons["[z]"] = list()
		GLOB.navbeacons["[z]"] += src //Register with the patrol list!
	if(codes[NAVBEACON_DELIVERY_MODE])
		GLOB.deliverybeacons += src
		GLOB.deliverybeacontags += location

/************************************Mob move procs************************************/

/mob/onShuttleMove(turf/newT, turf/oldT, list/movement_force, move_dir, obj/docking_port/stationary/old_dock, obj/docking_port/mobile/moving_dock)
	if(!move_on_shuttle)
		return
	. = ..()

/mob/afterShuttleMove(turf/oldT, list/movement_force, shuttle_dir, shuttle_preferred_direction, move_dir, rotation)
	if(!move_on_shuttle)
		return
	. = ..()
	if(client && movement_force)
		var/shake_force = max(movement_force["THROW"], movement_force["KNOCKDOWN"])
		if(buckled)
			shake_force *= 0.25
		shake_camera(src, shake_force, 1)

/mob/living/lateShuttleMove(turf/oldT, list/movement_force, move_dir)
	if(buckled)
		return

	. = ..()

	var/knockdown = movement_force["KNOCKDOWN"]
	if(knockdown)
		Paralyze(knockdown)


/mob/living/simple_animal/hostile/megafauna/onShuttleMove(turf/newT, turf/oldT, list/movement_force, move_dir, obj/docking_port/stationary/old_dock, obj/docking_port/mobile/moving_dock)
	. = ..()
	message_admins("Megafauna [src] [ADMIN_FLW(src)] moved via shuttle from [ADMIN_COORDJMP(oldT)] to [ADMIN_COORDJMP(loc)]")

/************************************Structure move procs************************************/

/obj/structure/grille/beforeShuttleMove(turf/newT, rotation, move_mode, obj/docking_port/mobile/moving_dock)
	. = ..()
	if(. & MOVE_AREA)
		. |= MOVE_CONTENTS

/obj/structure/lattice/beforeShuttleMove(turf/newT, rotation, move_mode, obj/docking_port/mobile/moving_dock)
	. = ..()
	if(. & MOVE_AREA)
		. |= MOVE_CONTENTS

/obj/structure/cable/beforeShuttleMove(turf/newT, rotation, move_mode, obj/docking_port/mobile/moving_dock)
	. = ..()
	cut_cable_from_powernet(FALSE)

/obj/structure/cable/afterShuttleMove(turf/oldT, list/movement_force, shuttle_dir, shuttle_preferred_direction, move_dir, rotation)
	. = ..()
	Connect_cable(TRUE)
	propagate_if_no_network()

/obj/machinery/power/shuttle_engine/beforeShuttleMove(turf/newT, rotation, move_mode, obj/docking_port/mobile/moving_dock)
	. = ..()
	if(. & MOVE_AREA)
		. |= MOVE_CONTENTS

/obj/structure/ladder/beforeShuttleMove(turf/newT, rotation, move_mode, obj/docking_port/mobile/moving_dock)
	. = ..()
	if (!(resistance_flags & INDESTRUCTIBLE))
		disconnect()

/obj/structure/ladder/afterShuttleMove(turf/oldT, list/movement_force, shuttle_dir, shuttle_preferred_direction, move_dir, rotation)
	. = ..()
	if (!(resistance_flags & INDESTRUCTIBLE))
		LateInitialize()

/obj/structure/ladder/onShuttleMove(turf/newT, turf/oldT, list/movement_force, move_dir, obj/docking_port/stationary/old_dock, obj/docking_port/mobile/moving_dock)
	if (resistance_flags & INDESTRUCTIBLE)
		// simply don't be moved
		return FALSE
	return ..()

/************************************Misc move procs************************************/

/obj/docking_port/mobile/beforeShuttleMove(turf/newT, rotation, move_mode, obj/docking_port/mobile/moving_dock)
	. = ..()
	if(moving_dock == src)
		. |= MOVE_CONTENTS

// Never move the stationary docking port, otherwise things get WEIRD
/obj/docking_port/stationary/onShuttleMove()
	return FALSE

// Holy shit go away
/obj/effect/abstract/z_holder/onShuttleMove()
	return FALSE

// Special movable stationary port, for your mothership shenanigans
/obj/docking_port/stationary/movable/onShuttleMove(turf/newT, turf/oldT, list/movement_force, move_dir, obj/docking_port/stationary/old_dock, obj/docking_port/mobile/moving_dock)
	if(!moving_dock.can_move_docking_ports || old_dock == src)
		return FALSE

	if(newT == oldT) // In case of in place shuttle rotation shenanigans.
		return

	if(loc != oldT) // This is for multi tile objects
		return

	abstract_move(newT)

	return TRUE

/obj/docking_port/stationary/public_mining_dock/onShuttleMove(turf/newT, turf/oldT, list/movement_force, move_dir, obj/docking_port/stationary/old_dock, obj/docking_port/mobile/moving_dock)
	shuttle_id = "mining_public" //It will not move with the base, but will become enabled as a docking point.
