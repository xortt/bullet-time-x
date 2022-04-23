class BulletTime : EventHandler
{
	// store time related data
	Array<BtSectorInfo> sectorInfoList;

	PlayerPawn btPlayerActivator;

	int btSecondTick; // on 35th tic it resets to 0

	// stores Monsters adrenaline related data, used with bullet time on and off
	Array<BtMonsterInfo> btMonsterInfoList;

	// render data (hud, fx)
	TextureID btSandClock;
	int btEffectCounter;
	bool btEffectInvulnerability;

	// main bullet time variables
	bool btActive;
	bool btHeartBeat;
	int btMultiplier;
	int btTic;
	int btMaxDurationMultiplier;
	int btMaxDurationCounter;

	int testTic;

	// post tick bt controller
	PostTickDummyController postTickController;

	override bool InputProcess(InputEvent e)
	{
		if (e.Type == InputEvent.Type_KeyDown)
			sendNetworkEvent("BtKeyDown", e.KeyScan);

		return false;
	}

	override void NetworkProcess(ConsoleEvent e)
	{
		int keys[4];
		[keys[0], keys[1]] = Bindings.GetKeysForCommand("BulletTime");
		[keys[2], keys[3]] = Bindings.GetKeysForCommand("+jump");
		if (e.Name == "BtKeyDown")
		{
			if ((keys[0] && keys[0] == e.Args[0]) || (keys[1] && keys[1] == e.Args[0]))
			{
				let player = PlayerPawn(players[e.player].mo);

				doSlowTime(!btActive, player);
			}
			if ((keys[2] && keys[2] == e.Args[0]) || (keys[3] && keys[3] == e.Args[0]))
			{
				let player = PlayerPawn(players[e.player].mo);
				Inventory btInv = player.FindInventory("BtItemData");
				BtItemData btItemData = btInv == NULL
						? BtItemData(player.GiveInventoryType("BtItemData"))
						: BtItemData(btInv);

				if (btItemData.actorInfo != NULL)
				{
					btItemData.actorInfo.playerJumpTic = 2;
				}
			}
		}
	}

	override void WorldLoaded(WorldEvent e)
	{
		// get cvars
		CVar cv;
		btMultiplier = cv.GetCVar("bt_multiplier").GetInt();
		btHeartBeat = cv.GetCVar("bt_heartbeat").GetInt();
		int btMaxDuration = clamp(cv.GetCVar("bt_max_duration").GetInt(), 15, 120);
		btMaxDurationMultiplier = round(btMaxDuration / 15);
		btMaxDurationCounter = 1;

		// initialize variables
		btEffectCounter = 0;
		btEffectInvulnerability = false;
		btSecondTick = 0;
		btSandClock = TexMan.CheckForTexture("SLCK", TexMan.Type_Any);
		testTic = 0;

		// removes all berserker counter when changing maps
		PlayerPawn doomPlayer;
		ThinkerIterator playerList = ThinkerIterator.Create("PlayerPawn", Thinker.STAT_PLAYER);

		while (doomPlayer = PlayerPawn(playerList.Next()) )
		{
			doomPlayer.SetInventory("BtBerserkerCounter", 0);
		}
	}

	override void WorldUnloaded(WorldEvent e) 
	{
		if (btActive && btPlayerActivator)
		{
			doSlowTime(false, btPlayerActivator); // returns everything to normal time
		}
	}

	override void WorldTick()
	{
		if (btActive)
		{
			slowGame(true);
		}

		// check if Player can keep using bullet time
		if (btPlayerActivator)
		{
			// hack to allow bullet time to last more if set in cvar bt_max_duration
			if (btMaxDurationCounter == btMaxDurationMultiplier)
			{
				btPlayerActivator.TakeInventory("BtAdrenaline", 1);
			}
			btMaxDurationCounter = btMaxDurationCounter >= btMaxDurationMultiplier ? 1 : btMaxDurationCounter + 1;

			bool canUseBulletTime = (btPlayerActivator.CheckInventory("BtBerserkerCounter", 1)) || btPlayerActivator.CheckInventory("BtAdrenaline", 1);
			if ((!canUseBulletTime || btPlayerActivator.health < 1) && (btPlayerActivator.floorz == btPlayerActivator.pos.z || BtHelperFunctions.checkPlayerIsSteppingActor(btPlayerActivator)))
			{
				doSlowTime(false, btPlayerActivator);
				return;
			}
		}

		// keeps track of Bullet Time FX Render effect
		if (btActive && btEffectCounter != 1) btEffectCounter = btEffectCounter == 0 ? 17 : btEffectCounter - 1;
		else if (!btActive) 
		{
			if (btEffectCounter > 0) btEffectCounter = -8; 
			else if (btEffectCounter < 0) btEffectCounter += 1;
		}


		if (btSecondTick == 35)
		{
			updateBtMonsterInfoList(); // on 35th tic, check for new monsters (spanwed, resurrected)
			btSecondTick = 0;
		}
		else btSecondTick++;

		handlePlayerAdrenaline();
		handlePlayerAdrenalineKills();

		btTic = btTic > btMultiplier ? 0 : btTic + 1;
	}

	/**
	* Draws Bullet Time related data onto the Hud, and also applies overlay special effects.
	**/
	override void RenderOverlay(RenderEvent e)
    {
        PlayerInfo p = players[consoleplayer];

		// enable shader that gives the white blink screen when enabling bullet time
		Shader.SetEnabled(players[consoleplayer], "btshader", true);
        Shader.SetUniform1f(players[consoleplayer], "btshader", "btEffectCounter", btEffectCounter);
        Shader.SetUniform1i(players[consoleplayer], "btshader", "btEffectInvulnerability", btEffectInvulnerability);
		
		bool hasBerserker = p.mo.CountInv("BtBerserkerCounter") > 0;
		double bulletTimeAmount = p.mo.CountInv("BtAdrenaline");
		double bulletTimeBerserkAmount = p.mo.CountInv("BtBerserkerCounter") / 2;

		int screenWidth = Screen.GetWidth();
		int screenHeight = Screen.GetHeight();

		double bulletTimeTotal = 525;

		// uiscale option
		CVar cv;
		int uiscale = clamp(cv.GetCVar("uiscale").GetInt() - 1, 1, 6);

		// sand clock dimensiones
		int width = 186 * uiscale;
		double height = 561 * uiscale;

		// draw sizes
		int destWidth = width / 5;
		int destHeight = height / 5;

		int offsetHeight = 50;
		int offsetWidth = screenWidth - destWidth - 50;

		// calculates image height based on bullet time counter
		double imageHeight = (height / uiscale) - ((height / uiscale) * (bulletTimeAmount / bulletTimeTotal));
		double berserkImageHeight = (height / uiscale) - ((height / uiscale) * (bulletTimeBerserkAmount / bulletTimeTotal));

		Screen.DrawTexture(
			btSandClock, 
			false, 
			offsetWidth, 
			offsetHeight, 
			DTA_Alpha, 0.25, 
			DTA_DestWidth, destWidth, 
			DTA_DestHeight, destHeight
		); // transparent background sand clock
		Screen.DrawTexture(
			btSandClock, 
			false, 
			offsetWidth, 
			offsetHeight, 
			DTA_SrcY, imageHeight, 
			DTA_DestWidth, destWidth, 
			DTA_DestHeight, destHeight, 
			DTA_TopOffsetF, -imageHeight
		); // bullet time sand clock

		if (hasBerserker) 
			Screen.DrawTexture(
				btSandClock, 
				false, 
				offsetWidth, 
				offsetHeight, 
				DTA_SrcY, berserkImageHeight, 
				DTA_Color, 0xFFcf1515, 
				DTA_DestWidth, destWidth, 
				DTA_DestHeight, destHeight, 
				DTA_TopOffsetF, -berserkImageHeight
			); // berserker overlay red clock



	}

	/**
	* Checks that player can actually start bullet time and starts it if apply slow is true.
	* When apply slow is false, bullet time stops and resets all actors / sectors velocities, tics.
	*/
	void doSlowTime(bool applySlow, PlayerPawn player)
	{
		bool hasBulletTimeCounter = (player.CheckInventory("BtBerserkerCounter", 1)) || player.CheckInventory("BtAdrenaline", 1);

		if (applySlow && (hasBulletTimeCounter || player.pos.z != player.floorz) && player.health > 0)
		{
			btTic = 0;
			player.A_StartSound("SLWSTART",  0, CHANF_LOCAL, 1.0, ATTN_NONE, 1.0);
			if (btHeartBeat) player.A_StartSound("SLWLOOP",  16, CHANF_LOOP, 1.0, ATTN_NONE, 1.0);

			postTickController = PostTickDummyController(player.Spawn("PostTickDummyController"));
			postTickController.btMultiplier = btMultiplier;
			postTickController.applySlow = true;
			
			btPlayerActivator = player;
			btActive = true;
			console.printf("Bullet Time!");
		} 
		else if (btActive)
		{
			slowGame(false);

			if (player) 
			{
				player.A_StartSound("SLWSTOP",  0, CHANF_LOCAL, 1.0, ATTN_NONE, 1.0);
				if (btHeartBeat) player.A_StopSound(16);
			}

			postTickController.applySlow = false;
			btPlayerActivator = null;
			btActive = false;
		}
	}

	/**
	* Checks if player's health went up or down, and gives adrenaline accordingly
	*/
	void handlePlayerAdrenaline()
	{
		PlayerPawn doomPlayer;
		ThinkerIterator playerList = ThinkerIterator.Create("PlayerPawn", Thinker.STAT_PLAYER);

		while (doomPlayer = PlayerPawn(playerList.Next()) )
		{
			Inventory btInv = doomPlayer.FindInventory("BtItemData");
			BtItemData btItemData = btInv == NULL
					? BtItemData(doomPlayer.GiveInventoryType("BtItemData"))
					: BtItemData(btInv);

			// check for existing user in 'player slow' data list
			bool createNewPlayerInfo = btItemData.adrenalinePlayerInfo == NULL;

			// if it doesn't have an adrenalinePlayerInfo initialized, then create it and set the actor pointer
			if (createNewPlayerInfo)
			{
				BtActorInfo actorInfo = new("BtActorInfo");
				actorInfo.playerRef = doomPlayer;
				btItemData.adrenalinePlayerInfo = actorInfo;

				btItemData.adrenalinePlayerInfo.playerRef = doomPlayer;
				btItemData.adrenalinePlayerInfo.lastHealth = doomPlayer.health;
			}

			// gives adrenaline based on player last health and current health
			int newHealth = doomPlayer.health;
			int oldHealth = btItemData.adrenalinePlayerInfo.lastHealth;
			if (newHealth != oldHealth)
			{
				int itemAmount = newHealth < oldHealth 
					? (oldHealth - newHealth) * 3.5 :  0;
				doomPlayer.GiveInventory("BtAdrenaline", itemAmount);
			}
			btItemData.adrenalinePlayerInfo.lastHealth = doomPlayer.health;

			// Loop through all items to check for powerups
			bool hasInvulnerability = false;
			for (Inventory item = doomPlayer.Inv; item != null; item = item.Inv)
			{
				Powerup powerUp = Powerup(item);
				if (powerUp) // if successful and exists then multiply powerup time
				{
					// gets name of powerup, if it kinda resembles berserker then add the bonus
					string powerUpName = powerUp.GetClassName();
					string powerUpNameLower = powerUpName.MakeLower();
					bool mightBeBerserker = powerUpNameLower.IndexOf("berserk") != -1 || powerUpNameLower.IndexOf("strength") != -1;

					if (mightBeBerserker) {
						int berserkerMaxTicEffect = 1050;
						int firstPowerUpTic = powerUp.Args[1];
						int currentPowerUpTic = powerUp.EffectTics;

						if (firstPowerUpTic != 0) 
						{
							int ticDiff = (firstPowerUpTic - currentPowerUpTic);

							if (ticDiff < 0 && currentPowerUpTic <= berserkerMaxTicEffect)
							{
								// forces player adrenaline to be at 100% when berserker counter effect is on (red screen)
								doomPlayer.GiveInventory("BtAdrenaline", 1000);
								doomPlayer.SetInventory("BtBerserkerCounter", berserkerMaxTicEffect - currentPowerUpTic);
							}
						}
						else
						{
							powerUp.Args[1] = powerUp.EffectTics;
						}
					}

					if (powerUpName == "PowerInvulnerable") 
					{
						hasInvulnerability = true;
					}
				}
			}
			btEffectInvulnerability = hasInvulnerability;

			if (doomPlayer.health <= 0) { // when player is dead take its all berserker counter so that sand clock doesn't remain red
				doomPlayer.SetInventory("BtBerserkerCounter", 0);
			}
		}
	}

	/**
	* When a player kills a Monster, grants adrenaline based on Monster health and damage done to it
	*/
	void handlePlayerAdrenalineKills()
	{
		for (int i = 0; i < btMonsterInfoList.Size(); i++) 
		{
			BtMonsterInfo curActor = btMonsterInfoList[i];

			// keeps tracks of attackers and second attackers
			if (curActor.actorRef) 
			{ 
				if (curActor.actorRef.target)
				{
					curActor.attacker = curActor.actorRef.target;
					curActor.secondAttacker = curActor.actorRef.target.target;
				}
			}

			// check if actor is dead and give adrenaline to killer
			if (!curActor.isDead && (!curActor.actorRef || curActor.actorRef.health <= 0))
			{ 
				if (curActor.attacker) 
				{
					int adrenalineValue = 20;
					if (curActor.actorRef)
					{
						// grants adrenaline based on damage done
						if (curActor.actorRef.health < -200) 
							adrenalineValue += 25;
					 	else if (curActor.actorRef.health < -100) 
							adrenalineValue += 17;
						else if (curActor.actorRef.health < -50) 
							adrenalineValue += 10;
						else if (curActor.actorRef.health < -20) 
							adrenalineValue += 5;

						// adrenaline based on monster health
						adrenalineValue += clamp(curActor.startHealth / 10, 0, 350);
					}

					if (!btActive) // grant only when bullet time is not enabled
						curActor.attacker.GiveInventory("BtAdrenaline", adrenalineValue);

					// second attacker is when a player hits an explosive barrel, and that kills the monster
					if (curActor.secondAttacker) {
						string firstClassName = curActor.attacker.GetClassName();
						string lwrFirstClassName = firstClassName.MakeLower();
						if (!btActive && firstClassName && lwrfirstClassName.IndexOf("barrel") != -1) {
							curActor.secondAttacker.GiveInventory("BtAdrenaline", adrenalineValue);
						}
					}
				}

				curActor.isDead = true; // monster is dead, do not give more adrenaline points
			}
			else if (curActor.isDead && curActor.actorRef && curActor.actorRef.health > 0)
			{ 
				curActor.isDead = false; // if actor resurrected, change it's status to not dead
			}
		}
	}

	/**
	* Creates / Updates Monster Info List. Actors that are considered monsters will be added.
	* This actors must have health higher than 0 and can be counted as kills.
	**/
	void updateBtMonsterInfoList()
	{
		Actor curActor;
		ThinkerIterator actorList = ThinkerIterator.Create("Actor", Thinker.STAT_DEFAULT);
		
		while (curActor = Actor(actorList.Next()))
		{
			Inventory btInv = curActor.FindInventory("BtItemData");
			BtItemData btItemData = btInv == NULL
					? BtItemData(curActor.GiveInventoryType("BtItemData"))
					: BtItemData(btInv);
			
			if (curActor.health > 0 && curActor.bCountKill && btItemData.monsterInfo == NULL)
			{
				BtMonsterInfo monsterInfo = new("BtMonsterInfo");

				monsterInfo.actorRef = curActor;
				monsterInfo.attacker = curActor.target;
				monsterInfo.startHealth = curActor.health;
				monsterInfo.isDead = false;

				if (curActor.target) monsterInfo.secondAttacker = curActor.target.target;
				else monsterInfo.secondAttacker = null;

				btItemData.monsterInfo = monsterInfo;
				btMonsterInfoList.Push(monsterInfo);
			}
		}
	}

	void slowGame(bool bulletTime) 
	{
		slowLightSectors(bulletTime);
		slowMovingSectors(bulletTime);
		slowPlayers(bulletTime);
		slowActors(bulletTime);
		slowScrollers(bulletTime);
		// slowDecals(bulletTime);
	}

	void slowActors(bool applySlow)
	{
		Actor curActor;
		ThinkerIterator actorList = ThinkerIterator.Create("Actor", Thinker.STAT_DEFAULT);

		while (curActor = Actor(actorList.Next()) )
		{
			Inventory btInv = curActor.FindInventory("BtItemData");
			BtItemData btItemData = btInv == NULL
					? BtItemData(curActor.GiveInventoryType("BtItemData"))
					: BtItemData(btInv);
			
			bool createNewActorInfo = btItemData.actorInfo == NULL;

			// if it doesn't have an actorInfo initialized, then create it and set the actor pointer
			if (createNewActorInfo)
			{
				BtActorInfo actorInfo = new("BtActorInfo");
				actorInfo.actorRef = curActor;
				btItemData.actorInfo = actorInfo;
			}

			if (createNewActorInfo || !applySlow)
			{ // apply first slowdown (if new to the info list) or go back to its original speed (if bt ended)
				curActor.vel = applySlow ? curActor.vel / btMultiplier : curActor.vel * btMultiplier;
				if (curActor.tics != -1)
					curActor.tics = applySlow ? curActor.tics * btMultiplier : curActor.tics / btMultiplier;
			}
			else if (!createNewActorInfo && applySlow)
			{ // when bt is on, slow down velocity constantly
				double velZZ = abs(curActor.vel.z - btItemData.actorInfo.lastVel.z);
				bool newZ = velZZ > 1.1 && abs(curActor.vel.z) < 1000; // last

				double velX = btItemData.actorInfo.lastVel.x != curActor.vel.x  && curActor.vel.x != 0
							? btItemData.actorInfo.lastVel.x + (curActor.vel.x - btItemData.actorInfo.lastVel.x) / btMultiplier
							: curActor.vel.x;
				double velY = btItemData.actorInfo.lastVel.y != curActor.vel.y && curActor.vel.y != 0
							? btItemData.actorInfo.lastVel.y + (curActor.vel.y - btItemData.actorInfo.lastVel.y) / btMultiplier
							: curActor.vel.y;
				double velZ = btItemData.actorInfo.lastVel.z != curActor.vel.z && (curActor.vel.z != 0 || (curActor.floorz != curActor.pos.z && curActor.ceilingz != curActor.pos.z + curActor.height))
							? btItemData.actorInfo.lastVel.z + (curActor.vel.z - btItemData.actorInfo.lastVel.z) / (btMultiplier * btMultiplier)
							: curActor.vel.z;

				if (newZ) velZ *= btMultiplier;
				if (velZZ > 1000) velZ = 0;
				curActor.vel = (velX, velY, velZ);

				if (btItemData.actorInfo.lastTics == 1 &&
					btItemData.actorInfo.lastState != curActor.CurState &&
					curActor.tics != -1)
				{ // when actor tics reached 1, slow it down by multiply the ticks again (or back to where it was when bt off)
					curActor.tics = (applySlow) ? curActor.tics * btMultiplier : curActor.tics / btMultiplier;
				}
			}
		
			// Slow sound pitch
			float soundPitch = applySlow ? clamp(2.0 / btMultiplier, 0.3, 1.0) : 1.0;
			for (int k = 0; k < 8; k++)
				curActor.A_SoundPitch(k, soundPitch);
			
			// save data for next tic when bt on
			btItemData.actorInfo.lastState = curActor.CurState;
			btItemData.actorInfo.lastTics = curActor.tics;
			btItemData.actorInfo.lastVel = curActor.vel;

			if (!applySlow) btItemData.actorInfo = NULL; // removes actorInfo, so that when reactivating bullet time, it is slowed down again
		}
	}

	void slowPlayers(bool applySlow)
	{
		PlayerPawn doomPlayer;
		ThinkerIterator playerList = ThinkerIterator.Create("PlayerPawn", Thinker.STAT_PLAYER);

		int weaponLayerAmount = 200; // -100 to 100

		while (doomPlayer = PlayerPawn(playerList.Next()) )
		{
			Inventory btInv = doomPlayer.FindInventory("BtItemData");
			BtItemData btItemData = btInv == NULL
					? BtItemData(doomPlayer.GiveInventoryType("BtItemData"))
					: BtItemData(btInv);

			bool createNewPlayerInfo = btItemData.actorInfo == NULL;

			// if it doesn't have an actorInfo initialized, then create it and set the actor pointer
			if (createNewPlayerInfo)
			{
				BtActorInfo actorInfo = new("BtActorInfo");
				actorInfo.playerRef = doomPlayer;
				btItemData.actorInfo = actorInfo;

				for (int j = 0; j < weaponLayerAmount; j++)
				{
					btItemData.actorInfo.lastWeaponTics[j] = 0; // initialize weapon tic array.
				}
			}

			// apply slow when new or restore speed when bullet time ends
			if (createNewPlayerInfo || !applySlow)
			{
				doomPlayer.speed = applySlow ? doomPlayer.speed / btMultiplier : btItemData.actorInfo.lastSpeed * btMultiplier;
				doomPlayer.vel = applySlow ? doomPlayer.vel / btMultiplier : btItemData.actorInfo.lastVel * btMultiplier;
				doomPlayer.viewBob = applySlow ? doomPlayer.viewBob / btMultiplier : doomPlayer.viewBob * btMultiplier;
			}
			else if (!createNewPlayerInfo && applySlow)
			{ // check for change in movement speed constantly

				// checks difference between last speed and current speed
				double velXY = (doomPlayer.vel.x - btItemData.actorInfo.lastVel.x, doomPlayer.vel.y - btItemData.actorInfo.lastVel.y).length();
				double velZZ = abs(doomPlayer.vel.z - btItemData.actorInfo.lastVel.z);

				// a hack here is applied to move 'smoother', because if doomguy gets slowdown ten times,
				// he will slide A LOT. This prevents that. And also checks for external forces (explosion from rocket, etc.)
				if (velXY > 1.1 && (btItemData.actorInfo.externalForce == 0 || btItemData.actorInfo.externalForce < velXY))
					btItemData.actorInfo.externalForce = velXY;
				else if (velXY > 1.1 && btItemData.actorInfo.externalForce > 1.1)
					btItemData.actorInfo.externalForce += (velXY / btMultiplier);
				else if (btItemData.actorInfo.externalForce < 1.1)
					btItemData.actorInfo.externalForce = 0;
				else if (btItemData.actorInfo.externalForce > 1.1)
					btItemData.actorInfo.externalForce = btItemData.actorInfo.externalForce - velXY;

				bool newZ = velZZ > 1.1; // doomguy received an external force or jumped, its vel z increased

				// when doomguy jumps a second time or when he receives an external velocity, reduce the last one so that
				// the sum on this next one is not too big, otherwise he'll go flying
				bool didJump = (btItemData.actorInfo.playerJumpTic == 2 && doomPlayer.vel.z > btItemData.actorInfo.lastVel.z) || (btItemData.actorInfo.playerJumpTic == 1 && doomPlayer.vel.z > 0 && doomPlayer.vel.z > btItemData.actorInfo.lastVel.z);
				if (didJump || newZ)
				{
					btItemData.actorInfo.lastVel.z /= ((btMultiplier * btMultiplier) / 2);
				} 

				double velX = btItemData.actorInfo.lastVel.x != doomPlayer.vel.x && btItemData.actorInfo.externalForce > 1.1 && doomPlayer.vel.x != 0
							? btItemData.actorInfo.lastVel.x + (doomPlayer.vel.x - btItemData.actorInfo.lastVel.x) / btMultiplier
							: doomPlayer.vel.x;
				double velY = btItemData.actorInfo.lastVel.y != doomPlayer.vel.y && btItemData.actorInfo.externalForce > 1.1 && doomPlayer.vel.y != 0
							? btItemData.actorInfo.lastVel.y + (doomPlayer.vel.y - btItemData.actorInfo.lastVel.y) / btMultiplier
							: doomPlayer.vel.y;
				double velZ = btItemData.actorInfo.lastVel.z != doomPlayer.vel.z && (doomPlayer.vel.z != 0 || (doomPlayer.floorz != doomPlayer.pos.z && doomPlayer.ceilingz != doomPlayer.pos.z + doomPlayer.height))
							? btItemData.actorInfo.lastVel.z + (doomPlayer.vel.z - btItemData.actorInfo.lastVel.z) / (btMultiplier * btMultiplier)
							: doomPlayer.vel.z;

				if ((newZ && btItemData.actorInfo.playerJumpTic == 0) || didJump) 
				{
					velZ *= btMultiplier;
				}

				// hack: sets velZ to 0 when stepping other actors, but allows velZ when jumping, also constraints velZ below 1000 if a glitch happens to prevent int overflow
				// this hack is done because when we step onto other actors, velZ is always > 0, because we are 'floating' above actors
				bool playerIsSteppingActor = BtHelperFunctions.checkPlayerIsSteppingActor(doomPlayer); 
				if ((playerIsSteppingActor && int(velZZ) != int(doomPlayer.jumpZ)) || velZZ > 1000) 
					velZ = 0;

				doomPlayer.vel = (velX, velY, velZ);

				// slows down speed as well, this is constant velocity
				double newSpeed = btItemData.actorInfo.lastSpeed != doomPlayer.speed
								? doomPlayer.speed / btMultiplier
								: doomPlayer.speed;

				doomPlayer.speed = newSpeed;
			}

			// Loop through all items to check for powerups
			for (Inventory item = doomPlayer.Inv; item != null; item = item.Inv)
			{
				Powerup powerUp = Powerup(item);
				if (powerUp) // if successful and exists then multiply powerup time
				{
					int slowAlreadyApplied = powerUp.Args[0];
					int firstPowerUpTic = powerUp.Args[1];
					int currentPowerUpTic = powerUp.EffectTics;
					int prevAndNewTicDifference = powerUp.Args[2];

					if (firstPowerUpTic != 0) 
					{
						int ticDiff = prevAndNewTicDifference == 0 ? (firstPowerUpTic - currentPowerUpTic) : prevAndNewTicDifference;
						
						// hack that checks whether powerup counter is going positive (berserker mostly) or negative (others)
						if (prevAndNewTicDifference == 0)
						{
							powerUp.Args[2] = ticDiff;	
						}

						// apply slow
						if (slowAlreadyApplied == 0 && applySlow && ticDiff > 0)
						{
							powerUp.EffectTics *= btMultiplier;
							powerUp.Args[0] = 1;
						} 
						else if (slowAlreadyApplied == 1 && !applySlow && ticDiff > 0)
						{
							powerUp.EffectTics /= btMultiplier;
							powerUp.Args[0] = 0;
						}
					}
					else
					{
						powerUp.Args[1] = currentPowerUpTic;
					}

				}
			}

			// slow down player current weapon, also its flash / overlay states
			Array<Int> weaponLayers;
			for (int i = -(int(weaponLayerAmount / 2)); i <= int(weaponLayerAmount / 2) - 1; i++) {
				weaponLayers.Push(i);
			}
			weaponLayers.Push(1000); // for overlay Flash

			for (int j = 0; j < weaponLayers.Size(); j++)
			{
				PSprite playerWp = doomPlayer.Player.FindPSprite(weaponLayers[j]);
				if (playerWp)
				{
					bool slowTicPlayer = (btItemData.actorInfo.lastWeaponTics[j] == 1 || 
										  createNewPlayerInfo || 
										  playerWp.CurState != btItemData.actorInfo.lastWeaponState[j]) 
										  ? true : false;
					if (slowTicPlayer || !applySlow)
					{
						playerWp.tics = (applySlow) ? playerWp.tics * btMultiplier : playerWp.tics / btMultiplier;
						if (playerWp.tics < 1) playerWp.tics = 1;
					}
					btItemData.actorInfo.lastWeaponState[j] = playerWp.CurState;
					btItemData.actorInfo.lastWeaponTics[j] = playerWp.tics;
				}
			}

			// slow or restore all player sounds
			float soundPitch = applySlow ? clamp(2.0 / btMultiplier, 0.3, 1.0) : 1.0;
			for (int k = 0; k < 8; k++)
				doomPlayer.A_SoundPitch(k, soundPitch);
			
			// change current floor/last floor damage interval
			if (!btItemData.actorInfo.lastSector)
			{
				btItemData.actorInfo.lastSector = doomPlayer.CurSector;
				doomPlayer.CurSector.damageinterval = applySlow 
					? doomPlayer.CurSector.damageinterval * btMultiplier 
					: doomPlayer.CurSector.damageinterval;
			}
			else if ((btItemData.actorInfo.lastSector && btItemData.actorInfo.lastSector != doomPlayer.CurSector) || !applySlow)
			{
				btItemData.actorInfo.lastSector.damageinterval /= btMultiplier;
				btItemData.actorInfo.lastSector = doomPlayer.CurSector;
				doomPlayer.CurSector.damageinterval = applySlow 
					? doomPlayer.CurSector.damageinterval * btMultiplier 
					: doomPlayer.CurSector.damageinterval;
			}

			btItemData.actorInfo.lastVel = doomPlayer.vel;
			btItemData.actorInfo.lastSpeed = doomPlayer.speed;
			btItemData.actorInfo.lastSector = doomplayer.CurSector;
			btItemData.actorInfo.playerJumpTic = btItemData.actorInfo.playerJumpTic > 0 ? btItemData.actorInfo.playerJumpTic - 1 : 0; // resets playerJumped check

			if (!applySlow) btItemData.actorInfo = NULL; // removes actorInfo, so that when reactivating bullet time, it is slowed down again
		}
	}

	void slowLightSectors(bool applySlow)
	{
		if (btTic >= btMultiplier)
		{
			Thinker lightThinker;
			ThinkerIterator testingList = ThinkerIterator.Create("Lighting", Thinker.STAT_STATIC);
			while (lightThinker = Thinker(testingList.Next()) )
			{
				lightThinker.changeStatNum(Thinker.STAT_LIGHT);
			}
		}
		else if (btTic == 0)
		{
			Thinker lightThinker;
			ThinkerIterator testingList = ThinkerIterator.Create("Lighting", Thinker.STAT_LIGHT);
			while (lightThinker = Thinker(testingList.Next()) )
			{
				lightThinker.changeStatNum(Thinker.STAT_STATIC);
			}
		}

		if (!applySlow)
		{
			Thinker lightThinker;
			ThinkerIterator testingList = ThinkerIterator.Create("Lighting", Thinker.STAT_STATIC);
			while (lightThinker = Thinker(testingList.Next()) )
			{
				lightThinker.changeStatNum(Thinker.STAT_LIGHT);
				
			}
		}
	}

// TODO: DBaseDecal (es una clase)
	void slowScrollers(bool applySlow)
	{
		if (btTic >= btMultiplier)
		{
			Thinker scrollerThinker;
			ThinkerIterator testingList = ThinkerIterator.Create("Object", Thinker.STAT_STATIC);
			while (scrollerThinker = Thinker(testingList.Next()) )
			{
				string thinkerClassName = scrollerThinker.GetClassName();
				if (thinkerClassName == "Scroller")
				{
					scrollerThinker.changeStatNum(Thinker.STAT_SCROLLER);
				}	
			}
		}
		else if (btTic == 0)
		{
			Thinker scrollerThinker;
			ThinkerIterator testingList = ThinkerIterator.Create("Object", Thinker.STAT_SCROLLER);
			while (scrollerThinker = Thinker(testingList.Next()) )
			{
				string thinkerClassName = scrollerThinker.GetClassName();
				if (thinkerClassName == "Scroller")
				{
					scrollerThinker.changeStatNum(Thinker.STAT_STATIC);
				}
			}
		}

		if (!applySlow)
		{
			Thinker scrollerThinker;
			ThinkerIterator testingList = ThinkerIterator.Create("Object", Thinker.STAT_STATIC);
			while (scrollerThinker = Thinker(testingList.Next()) )
			{
				string thinkerClassName = scrollerThinker.GetClassName();
				if (thinkerClassName == "Scroller")
				{
					scrollerThinker.changeStatNum(Thinker.STAT_SCROLLER);
				}	
			}
		}
	}

	// void slowDecals(bool applySlow)
	// {
	// 	console.printf("TESTINGGGG %d", testTic);
	// 	if (testTic == 75)
	// 	{
	// 		Thinker scrollerThinker;
	// 		ThinkerIterator testingList = ThinkerIterator.Create("Object", Thinker.STAT_STATIC);
	// 		while (scrollerThinker = Thinker(testingList.Next()) )
	// 		{
	// 			string thinkerClassName = scrollerThinker.GetClassName();
	// 			console.printf("thinker class name is 111 %s", thinkerClassName);
	// 			if (thinkerClassName == "DecalFader")
	// 			{
	// 				// console.printf("TESTING TIC IS %d", scrollerThinker.tics);
	// 				scrollerThinker.changeStatNum(Thinker.STAT_DECALTHINKER);
	// 			}	
	// 		}
	// 	}
	// 	else if (testTic <= 76)
	// 	{
	// 		console.printf("TEST TIC IS 2222222222 %d", testTic);
	// 		Thinker scrollerThinker;
	// 		ThinkerIterator testingList = ThinkerIterator.Create("Object", Thinker.STAT_DECALTHINKER);
	// 		while (scrollerThinker = Thinker(testingList.Next()) )
	// 		{
	// 			string thinkerClassName = scrollerThinker.GetClassName();
	// 			console.printf("thinker class name is 22222  %s", thinkerClassName);
	// 			if (thinkerClassName == "DecalFader")
	// 			{
	// 				// console.printf("222222 TESTING TIC IS %d", scrollerThinker.tics);
	// 				scrollerThinker.changeStatNum(Thinker.STAT_STATIC);
	// 			}
	// 		}
	// 	}
	// 	testTic++;

	// 	if (testTic > 150) testTic = 0;

	// 	// if (!applySlow)
	// 	// {
	// 	// 	Thinker scrollerThinker;
	// 	// 	ThinkerIterator testingList = ThinkerIterator.Create("DecalFader", Thinker.STAT_STATIC);
	// 	// 	while (scrollerThinker = Thinker(testingList.Next()) )
	// 	// 	{
	// 	// 		string thinkerClassName = scrollerThinker.GetClassName();
	// 	// 		console.printf("thinker class name is 3333 %s", thinkerClassName);
	// 	// 		if (thinkerClassName == "DecalFader")
	// 	// 		{
	// 	// 			scrollerThinker.changeStatNum(Thinker.STAT_SCROLLER);
	// 	// 		}	
	// 	// 	}
	// 	// }
	// }

	void slowMovingSectors(bool applySlow)
	{
		sectorInfoList.Move(postTickController.sectorInfoList); // update array

		Thinker thinkerSector;
		ThinkerIterator sectorMovingList = ThinkerIterator.Create("SectorEffect", Thinker.STAT_SECTOREFFECT);

		while (thinkerSector = Thinker(sectorMovingList.Next()) ) // look for new SectorEffects or ticking ones
		{
			SectorEffect se = SectorEffect(thinkerSector);
			Sector sec = se.getSector();

			bool createNewSectorInfo = true;
			for (int i = 0; i < sectorInfoList.Size(); i++)
			{
				if (sectorInfoList[i].sectorID == sec.sectornum)
				{
					createNewSectorInfo = false;
					break;
				}
			}

			if (createNewSectorInfo)
			{
				sectorInfoList.Push(BtSectorInfo.initialize(sec, thinkerSector));

				// disables ticking on this sector
				thinkerSector.changeStatNum(Thinker.STAT_STATIC); 
			}
		}


		Array<int> itemsToDel;

		for (int j = 0; j < sectorInfoList.Size(); j++)
		{
			if (!sectorInfoList[j].thinkerRef)
			{ // sector is not moving anymore, remove it from list
				itemsToDel.Push(sectorInfoList[j].sectorID);
				continue;
			}
			if (!btActive)
			{
				sectorInfoList[j].thinkerRef.changeStatNum(Thinker.STAT_SECTOREFFECT); // enables sector to move again
			}

			SectorEffect se = SectorEffect(sectorInfoList[j].thinkerRef);
			Sector sec = se.getSector();

			// when ticking reaches X and goes back to 0, apply slow down
			if (sectorInfoList[j].tics == 0) // may have a problem when floor stops but ceiling doesnt..
			{
				// FLOOR LOGIC
				double floorSpeed = (sectorInfoList[j].floorPos - sec.floorplane.D);
				double slowFloorSpeed = floorSpeed / btMultiplier;
				double floorDeltaSpeed = floorSpeed - slowFloorSpeed;
				int floorMoveDir = floorSpeed < 0 ? 1 : -1;

				// CEILING LOGIC
				double ceilingSpeed = (sectorInfoList[j].ceilingPos - sec.ceilingplane.D);
				double slowCeilingSpeed = ceilingSpeed / btMultiplier;
				double ceilingDeltaSpeed = ceilingSpeed - slowCeilingSpeed;
				int ceilingMoveDir = ceilingSpeed < 0 ? 1 : -1;

				if (!sectorInfoList[j].hasStopped)
				{
					// move both upwards, then engine corrects it moving it downwards.
					// one will not move if speed = 0, so no worries there
					sec.MoveFloor(floorDeltaSpeed, sec.floorplane.D - (floorDeltaSpeed * floorMoveDir), 0, -floorMoveDir, false); 
					sec.MoveCeiling(ceilingDeltaSpeed, sec.ceilingplane.D - (ceilingDeltaSpeed * ceilingMoveDir), 0, ceilingMoveDir, false); // move floor upwards, then engine corrects it moving it downwards. 

					sectorInfoList[j].floorSpeed = floorDeltaSpeed;
					sectorInfoList[j].ceilingSpeed = ceilingDeltaSpeed;
				}
			}

			sectorInfoList[j].floorPos = sec.floorplane.D;
			sectorInfoList[j].ceilingPos = sec.ceilingplane.D;
		}

		// delete unused sectors
		if (itemsToDel.Size() > 0)
		{
			for (int i = 0; i < itemsToDel.Size(); i++)
			{
				for (int j = 0; j < sectorInfoList.Size(); j++)
				{
					if (sectorInfoList[j].sectorID == itemsToDel[i])
					{
						sectorInfoList.Delete(j);
						break;
					}
				}
			}
		}
		if (!btActive)
		{
			sectorInfoList.Clear();
		}

		postTickController.sectorInfoList.Move(sectorInfoList); // update values for post tick array
	}
}