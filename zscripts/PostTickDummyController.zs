/*
	PostTickDummyController is used to control thinkers POST tick.
	When spawned, its thinker priority number is the last one, so it will always be
	the last one on the list to run the script.
	This is very useful to correct actor, sector behaviors when on bullet time.
*/
class PostTickDummyController : Actor
{
	Array<BtSectorInfo> sectorInfoList;
	bool applySlow;

	int btMultiplier;
	int btPlayerMovementMultiplier;
	int btPlayerWeaponSpeedMultiplier;

	override void beginPlay()
	{
		CVar cv;
		changeStatNum(126); // changes tick stat number to one that no actor uses, so that when going through actor thinker lists, it's only this one
	}

	override void tick()
	{
		slowMovingSectors();
		slowPlayers();

		if (!applySlow)
		{
			destroy();
		}
	}

	void slowMovingSectors()
	{
		for (int j = 0; j < sectorInfoList.Size(); j++)
		{
			if (!sectorInfoList[j].thinkerRef)
			{
				continue; // sector is not moving, removal is done pre tick, not here.
			}

			SectorEffect se = SectorEffect(sectorInfoList[j].thinkerRef);
			Sector sec = se.getSector();

			bool fixStoppedSectorPos = false;

			if (sectorInfoList[j].tics > 0) // slow down ticking, nothing happens here
			{
				sectorInfoList[j].tics--;

				if (sectorInfoList[j].tics == 0) // if it reaches 0, start movement
				{
					sectorInfoList[j].thinkerRef.changeStatNum(Thinker.STAT_SECTOREFFECT); // allow sector ticking on NEXT TIC.
				}
			}
			else if (sectorInfoList[j].tics < 0) // sectoreffect just spawned, works for most of elevators
			{
				// tic -2 is a dummy, so that the engine doesnt do anything weird
				// tic -1 moves sector in inverse direction so that in the next tic the handler can move it without any anomalies
				fixStoppedSectorPos = true;

				// Apply speed so when bullet time starts it knows whether the sector is moving or not
				// FLOOR LOGIC
				double floorSpeed = (sectorInfoList[j].floorPos - sec.floorplane.D);
				double slowFloorSpeed = floorSpeed / btMultiplier;
				double floorDeltaSpeed = floorSpeed - slowFloorSpeed;

				// CEILING LOGIC
				double ceilingSpeed = (sectorInfoList[j].ceilingPos - sec.ceilingplane.D);
				double slowCeilingSpeed = ceilingSpeed / btMultiplier;
				double ceilingDeltaSpeed = ceilingSpeed - slowCeilingSpeed;

				sectorInfoList[j].ceilingSpeed = ceilingDeltaSpeed;
				sectorInfoList[j].floorSpeed = floorDeltaSpeed;

				sectorInfoList[j].thinkerRef.changeStatNum(Thinker.STAT_SECTOREFFECT); // allow sector ticking on NEXT TIC.
				sectorInfoList[j].tics++;
			}
			else if (sectorInfoList[j].tics == 0 && sectorInfoList[j].hasStopped)
			{ // restart timer if floor or ceiling is still stopped
				sectorInfoList[j].tics = btMultiplier;
				sectorInfoList[j].thinkerRef.changeStatNum(Thinker.STAT_STATIC);
			}

			// when floor/ceil was moving and stopped
			bool engineFloorNotMoving = (sec.floorplane.D - sectorInfoList[j].floorPos == 0 && !sectorInfoList[j].hasStopped && sectorInfoList[j].floorSpeed != 0);
			bool engineCeilingNotMoving = (sec.ceilingplane.D - sectorInfoList[j].ceilingPos == 0 && !sectorInfoList[j].hasStopped && sectorInfoList[j].ceilingSpeed != 0);
			// when bullettime started and floor/ceil was 'stopped'
			bool startFloorNotMoving = (sectorInfoList[j].tics == 0 && sectorInfoList[j].floorSpeed == 0 && !sectorInfoList[j].hasStopped);
			bool startCeilingNotMoving = (sectorInfoList[j].tics == 0 && sectorInfoList[j].ceilingSpeed == 0 && !sectorInfoList[j].hasStopped);
			// when floor/ceil was stopped, and started moving again
			bool floorRestarted = (sec.floorplane.D - sectorInfoList[j].floorPos != 0 && sectorInfoList[j].hasStopped);
			bool ceilingRestarted = (sec.ceilingplane.D - sectorInfoList[j].ceilingPos != 0 && sectorInfoList[j].hasStopped);

			if ((engineFloorNotMoving || startFloorNotMoving) && (engineCeilingNotMoving || startCeilingNotMoving))
			{
				// stops floor and force mantain pos, also starts tic timer
				sectorInfoList[j].hasStopped = true;
				sectorInfoList[j].tics = btMultiplier;
				sectorInfoList[j].thinkerRef.changeStatNum(Thinker.STAT_STATIC);

				sec.MoveFloor(abs(sectorInfoList[j].floorSpeed), sectorInfoList[j].postFloorPos, 0, -1, false); // move to stopping position and stay there
				sec.MoveCeiling(abs(sectorInfoList[j].ceilingSpeed), sectorInfoList[j].postCeilingPos, 0, -1, false); // move to stopping position and stay there 
			}
			else if (floorRestarted || ceilingRestarted)
			{
				// allows floor to move again
				sectorInfoList[j].hasStopped = false;
				sectorInfoList[j].tics = 0;
				sectorInfoList[j].thinkerRef.changeStatNum(Thinker.STAT_SECTOREFFECT);

				fixStoppedSectorPos = true;				
			}

			// move floor or ceiling 2 times its inverted speed
			// this is to smooth the start and stop of the sector effect
			if (fixStoppedSectorPos)
			{
				// floor
				double floorSpeed = (sectorInfoList[j].floorPos - sec.floorplane.D);
				int floorMoveDir = floorSpeed < 0 ? 1 : -1;

				sectorInfoList[j].floorPos = sec.floorplane.D + (floorSpeed * 2);
				sec.MoveFloor(floorSpeed, sec.floorplane.D - (floorSpeed * floorMoveDir), 0, -floorMoveDir, false);

				// ceiling
				double ceilingSpeed = (sectorInfoList[j].ceilingPos - sec.ceilingplane.D);
				int ceilingMoveDir = ceilingSpeed < 0 ? 1 : -1;

				sectorInfoList[j].ceilingPos = sec.ceilingplane.D + (ceilingSpeed * 2);
				sec.MoveCeiling(ceilingSpeed, sec.ceilingplane.D - (ceilingSpeed * ceilingMoveDir), 0, ceilingMoveDir, false);
			}

			sectorInfoList[j].postFloorPos = sec.floorplane.D;
			sectorInfoList[j].postCeilingPos = sec.ceilingplane.D;

			if (!applySlow)
			{
				sectorInfoList[j].thinkerRef.changeStatNum(Thinker.STAT_SECTOREFFECT); // allow sector ticking on NEXT TIC.
			}
		}
	}

	void slowPlayers()
	{
		PlayerPawn doomPlayer;
		ThinkerIterator playerList = ThinkerIterator.Create("PlayerPawn", Thinker.STAT_PLAYER);

		while (doomPlayer = PlayerPawn(playerList.Next()) )
		{
			bool isVoodooDoll = BtHelperFunctions.isPlayerPawnVoodooDoll(doomPlayer);
			if (isVoodooDoll) continue;
			
			for (int k = 0; k < sectorInfoList.Size(); k++)
			{
				// check if player is on a lift
				// this will fix some Z anomalies with the camera
				if (sectorInfoList[k].sectorID == doomPlayer.CurSector.sectornum && sectorInfoList[k].floorSpeed != 0)
				{
					double distancePlayerFloor = abs(doomPlayer.floorz - doomPlayer.pos.z);

					if (doomPlayer.pos.z != doomPlayer.floorz && doomPlayer.vel.z == 0 && distancePlayerFloor < abs(sectorInfoList[k].floorSpeed) * 2)
					{
						// change camera z pos
						double cameraPosZOffset = doomPlayer.player.viewz - doomPlayer.pos.z;
						double newCameraPosZ = cameraPosZOffset + doomPlayer.floorz;
						doomPlayer.player.viewZ = newCameraPosZ;

						// fix player pos
						doomPlayer.SetOrigin((doomPlayer.pos.x, doomPlayer.pos.y, doomPlayer.floorz), true);
					}
					if (doomPlayer.pos.z == doomPlayer.floorz && sectorInfoList[k].floorSpeed > 0 && doomPlayer.vel.z != 0)
					{
						doomPlayer.vel.z = 0;
					}
				}
			}

			// Slow sound pitch
			float soundPitch = applySlow ? BtHelperFunctions.calculateSoundPitch(btPlayerWeaponSpeedMultiplier) : 1.0;
			for (int k = 0; k < 8; k++)
				doomPlayer.A_SoundPitch(k, soundPitch);
		
			Inventory btInv = doomPlayer.FindInventory("BtItemData");
			BtItemData btItemData = btInv == NULL
					? BtItemData(doomPlayer.GiveInventoryType("BtItemData"))
					: BtItemData(btInv);
			
			if (btItemData.actorInfo != NULL) 
			{
				// check that the last new speed is not the same as the one right now
				// this happens when a mod changes player's speed value constantly because it goes lower than a certain value
				// this prevents that
				if (btItemData.actorInfo.newChangedSpeed == doomPlayer.speed)
				{
					double newSpeed = btItemData.actorInfo.lastSpeed != doomPlayer.speed
									? doomPlayer.speed / btPlayerMovementMultiplier
									: doomPlayer.speed;
					doomPlayer.speed = newSpeed;
				}
				else if (btItemData.actorInfo.lastSpeed != doomPlayer.speed)
				{
					btItemData.actorInfo.newChangedSpeed = doomPlayer.speed;
				}
			}
		}
	}
}