class BulletTime : EventHandler
{
	enum Constants
	{
		SOUND_START_COUNTER = 35,
	}

	// store time related data
	Array<BtSectorInfo> sectorInfoList;

	PlayerPawn btPlayerActivator;

	int btOneSecondTick; // on 35th tic it resets to 0

	// stores Monsters adrenaline related data, used with bullet time on and off
	Array<BtMonsterInfo> btMonsterInfoList;

	// sound data
	int btSoundStartCounter;

	// render data (hud, fx)
	TextureID btSandClock;
	int btEffectCounter;
	int btBlurEffectCounter;
	bool btEffectInvulnerability;

	// main bullet time variables
	bool btActive;
	bool btDodgeActive;
	bool btBerserkActive;
	bool btConsoleActive; // only used when player activates bt through console cmd
	int btTic;
	int btDurationCounter;

	int btMultiplier;
	int btPlayerMovementMultiplier;
	int btPlayerWeaponSpeedMultiplier;

	// cvar options (only changed when they are initialized)
	int cvBtMultiplier;
	int cvBtPlayerMovementMultiplier;
	int cvBtPlayerWeaponSpeedMultiplier;
	bool cvBtPlayerModelSlowdown;

	bool cvBtDodgeEnable;
	int cvBtDodgeMultiplier;
	int cvBtDodgePlayerMovementMultiplier;
	int cvBtDodgePlayerWeaponSpeedMultiplier;

	bool cvBtBerserkEffectEnable;
	int cvBtBerserkEffectDuration;
	int cvBtBerserkMultiplier;
	int cvBtBerserkPlayerMovementMultiplier;
	int cvBtBerserkPlayerWeaponSpeedMultiplier;
	int cvBtBerserkDodgeMultiplier;
	int cvBtBerserkDodgePlayerMovementMultiplier;
	int cvBtBerserkDodgePlayerWeaponSpeedMultiplier;

	int cvBtAdrenalineDuration;
	int cvBtAdrenalineDurationMultiplier;
	int cvBtAdrenalineRegenSpeed;
	int cvBtSoundStartType;
	int cvBtSoundDodgeType;
	int cvBtSoundLoopType;
	int cvBtSoundStopType;
	float cvBtAdrenalineKillRewardMultiplier;
	float cvBtAdrenalinePlayerDamageRewardMultiplier;
	float cvBtMusicVolume;
	bool cvBtAdrenalineUnlimited;
	bool cvBtAdrenalineKillRewardWhenActive;
	bool cvBtHideMessage;
	bool cvBtShaderWhiteBlink;
	bool cvBtShaderBlur;

	// post tick bt controller
	PostTickDummyController postTickController;

	override void NetworkProcess(ConsoleEvent e)
	{
		if (e.Name == "bt_activate")
		{
			let player = PlayerPawn(players[e.player].mo);
			btConsoleActive = true; // slow down will happen on the next tic

			if (btPlayerActivator == null) btPlayerActivator = player;
		}

		if (e.Name == "bt_activate_dodge")
		{
			let player = PlayerPawn(players[e.player].mo);

			// if crouched don't dodge, cause can't jump
			if (player.player.cmd.buttons & BT_CROUCH) return;

			// forces player to jump
			player.player.cmd.buttons |= BT_JUMP;
			player.CheckJump();

			Inventory btInv = player.FindInventory("BtItemData");
			BtItemData btItemData = btInv == NULL
					? BtItemData(player.GiveInventoryType("BtItemData"))
					: BtItemData(btInv);

			if (btItemData.actorInfo != NULL)
			{
				btItemData.actorInfo.playerJumpTic = 2;
			}
			if (btItemData.adrenalinePlayerInfo != NULL) // for dodge bullet time
			{
				btItemData.adrenalinePlayerInfo.playerJumpTic = 2;
				btItemData.adrenalinePlayerInfo.playerDodged = true;
			}
		}
	}

	override void WorldLoaded(WorldEvent e)
	{
		initCvarVariables();

		// get cvars
		CVar cv;

		cvBtAdrenalineUnlimited = clamp(cv.GetCVar("bt_adrenaline_unlimited").GetInt(), 0, 1);
		cvBtAdrenalineKillRewardWhenActive = clamp(cv.GetCVar("bt_adrenaline_kill_reward_when_active").GetInt(), 0, 1);
		cvBtAdrenalineKillRewardMultiplier = clamp(cv.GetCVar("bt_adrenaline_kill_reward_multiplier").GetFloat(), 0, 10);
		cvBtAdrenalinePlayerDamageRewardMultiplier = clamp(cv.GetCVar("bt_adrenaline_player_damage_reward_multiplier").GetFloat(), 0, 10);
		cvBtAdrenalineRegenSpeed = clamp(cv.GetCVar("bt_adrenaline_regen_speed").GetInt(), 0, 35);
		cvBtAdrenalineDuration = clamp(cv.GetCVar("bt_adrenaline_duration").GetInt(), 5, 120);

		cvBtBerserkEffectDuration = clamp(cv.GetCVar("bt_berserk_effect_duration").GetInt(), 5, 120);

		// initialize variables
		btMultiplier = cvBtMultiplier;
		btPlayerMovementMultiplier = cvBtPlayerMovementMultiplier;
		btPlayerWeaponSpeedMultiplier = cvBtPlayerWeaponSpeedMultiplier;

		btBerserkActive = false;
		btDodgeActive = false;

		cvBtAdrenalineDurationMultiplier = clamp(round(cvBtAdrenalineDuration / 5), 1, 24); // 5 is the min duration (in secs)
		btDurationCounter = 1;

		// render variables
		btEffectCounter = 0;
		btEffectInvulnerability = false;
		btOneSecondTick = 0;
		btSandClock = TexMan.CheckForTexture("SLCK", TexMan.Type_Any);

		// removes all berserker counter when changing maps
		PlayerPawn doomPlayer;
		ThinkerIterator playerList = ThinkerIterator.Create("PlayerPawn", Thinker.STAT_PLAYER);

		while (doomPlayer = PlayerPawn(playerList.Next()) )
		{
			bool isVoodooDoll = BtHelperFunctions.isPlayerPawnVoodooDoll(doomPlayer);
			if (isVoodooDoll) continue;
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
		if (btConsoleActive)
		{
			btConsoleActive = false;
			doSlowTime(!btActive, btPlayerActivator);
		}

		bool doUpdateMonsterInfoList = btOneSecondTick == 35;
		bool forceDoSlowGame = false;

		handlePlayerAdrenaline(forceDoSlowGame);
		handlePlayerAdrenalineKills();

		if (btActive)
		{
			bool fromMultiplierChange = applyMultipliers(forceDoSlowGame);
			slowGame(true, doUpdateMonsterInfoList, fromMultiplierChange);

			// btTic will be 0 when bullet time just started, but always > 1 afterwards
			btTic = btTic > (btMultiplier + 1) ? 1 : btTic + 1;
		}
		else if (doUpdateMonsterInfoList)
		{
			trackActors(false, false, doUpdateMonsterInfoList, false); // on 35th tic, check for new monsters (spanwed, resurrected)
		}

		// counter for updating monster info list every 35 tics.
		if (doUpdateMonsterInfoList) btOneSecondTick = 0;
		else btOneSecondTick++;

		// check if Player can keep using bullet time
		if (btPlayerActivator)
		{
			int adrenalineAmount = cvBtAdrenalineUnlimited ? 525 : btPlayerActivator.CountInv("BtAdrenaline");

			// hack to allow bullet time to last more if set in cvar bt_max_duration
			if (btDurationCounter == cvBtAdrenalineDurationMultiplier)
			{
				btPlayerActivator.TakeInventory("BtAdrenaline", 3);
			}

			if (cvBtSoundLoopType != 0 && btSoundStartCounter >= SOUND_START_COUNTER && btActive && !btDodgeActive)
			{ // checks if sound is different from the last one, if so, then change it. Also starts the sound 2 secs after bullet time starts (to prevent overlapping sounds)
				string soundTypeLoopPrefix = BtHelperFunctions.getSoundTypeLoop(cvBtSoundLoopType, adrenalineAmount, cvBtAdrenalineDuration);
				string soundTypeLoopPostfix = BtHelperFunctions.getSoundTypeLoop(cvBtSoundLoopType, clamp(adrenalineAmount - 3, 0, 525), cvBtAdrenalineDuration);

				if (soundTypeLoopPrefix != soundTypeLoopPostfix || btSoundStartCounter == SOUND_START_COUNTER) 
				{
					btPlayerActivator.A_StartSound(soundTypeLoopPostfix, 16, CHANF_LOOP, 1.0, ATTN_NONE, 1.0);
				}
			}
	
			btDurationCounter = btDurationCounter >= cvBtAdrenalineDurationMultiplier ? 1 : btDurationCounter + 1;
			btSoundStartCounter = btSoundStartCounter > SOUND_START_COUNTER ? btSoundStartCounter : btSoundStartCounter + 1;

			// disables bullet time when ran out of adrenaline / player hit floor or step onto another actor
			bool canUseBulletTime = (btPlayerActivator.CheckInventory("BtBerserkerCounter", 1)) || btPlayerActivator.CheckInventory("BtAdrenaline", 1) || cvBtAdrenalineUnlimited;
			bool steppingFloorOrActor = (btPlayerActivator.floorz == btPlayerActivator.pos.z || BtHelperFunctions.checkPlayerIsSteppingActor(btPlayerActivator));
			if ((!canUseBulletTime && steppingFloorOrActor) || btPlayerActivator.health < 1)
			{
				doSlowTime(false, btPlayerActivator);
				return;
			}
		}

		// keeps track of Bullet Time FX Render effect
		if (btActive && btEffectCounter != 1) btEffectCounter = btEffectCounter == 0 ? 17 : clamp(btEffectCounter - 1, -8, 17);
		else if (!btActive) 
		{
			if (btEffectCounter > 0) btEffectCounter = -8; 
			else if (btEffectCounter < 0) btEffectCounter += 1;
		}

		// keeps track of Bullet Time FX Blur effect
		if (cvBtShaderBlur && btBlurEffectCounter > 0) btBlurEffectCounter--;
	}

	/**
	* Draws Bullet Time related data onto the Hud, and also applies overlay special effects.
	**/
	override void RenderOverlay(RenderEvent e)
    {
        PlayerInfo p = players[consoleplayer];

		// enable shader that gives the white blink screen when enabling bullet time
		if (cvBtShaderWhiteBlink) 
		{
			Shader.SetEnabled(players[consoleplayer], "btshader", true);
			Shader.SetUniform1f(players[consoleplayer], "btshader", "btEffectCounter", btEffectCounter);
			Shader.SetUniform1i(players[consoleplayer], "btshader", "btEffectInvulnerability", btEffectInvulnerability);
		}

		// enable shader that gives the blur effect when enabling bullet time
		if (cvBtShaderBlur)
		{
			int samples = 10;
			int distanceSteps = 3;

			double feedbackLoopEffectCounter = double(abs(btBlurEffectCounter * distanceSteps));

			vector2 distance = (feedbackLoopEffectCounter / screen.getwidth(), feedbackLoopEffectCounter / screen.getheight());
			int copies = feedbackLoopEffectCounter != 0 ? abs(feedbackLoopEffectCounter) : 1;
			double increment = 1. / copies;

			Shader.SetEnabled(players[consoleplayer], "btloop", true);
			Shader.SetUniform2f(players[consoleplayer], "btloop", "steps", distance * increment);
			Shader.SetUniform1i(players[consoleplayer], "btloop", "samples", copies);
			Shader.SetUniform1f(players[consoleplayer], "btloop", "increment", increment);
		}
		
		// shader calculations for drawing sand clocks
		if (!cvBtAdrenalineUnlimited)
		{
			bool hasBerserker = p.mo.CountInv("BtBerserkerCounter") > 0;
			double bulletTimeAmount = p.mo.CountInv("BtAdrenaline");
			double bulletTimeBerserkAmount = p.mo.CountInv("BtBerserkerCounter");
			int screenWidth = Screen.GetWidth();
			int screenHeight = Screen.GetHeight();

			double bulletTimeTotal = 525;

			// uiscale option
			CVar cv;
			float cvBtCounterHorizontalOffset = float(clamp(cv.GetCVar("bt_counter_horizontal_offset").GetInt(), 0, 100)) / 100;
			float cvBtCounterVerticalOffset = float(clamp(cv.GetCVar("bt_counter_vertical_offset").GetInt(), 0, 100)) / 100;
			int cvBtCounterScale = clamp(cv.GetCVar("bt_counter_scale").GetInt(), 1, 10);
			int uiscale = clamp(cv.GetCVar("uiscale").GetInt() - 1, 1, 4);

			// sand clock dimensiones
			int width = 186 * uiscale;
			double height = 561 * uiscale;

			// draw sizes
			// 15 is max size, so we use 16 to prevent division with 0 when scaling.
			int destWidth = width / (16 - (cvBtCounterScale * 1.5));
			int destHeight = height / (16 - (cvBtCounterScale * 1.5));

			int offsetWidth = (screenWidth * cvBtCounterHorizontalOffset) - (destWidth * cvBtCounterHorizontalOffset);
			int offsetHeight = (screenHeight * cvBtCounterVerticalOffset) - (destHeight * cvBtCounterVerticalOffset);

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
	}

	void initCvarVariables()
	{
		CVar cv;

		cvBtHideMessage = clamp(cv.GetCVar("bt_hide_message").GetInt(), 0, 1);

		cvBtShaderWhiteBlink = clamp(cv.GetCVar("bt_shader_white_blink_enable").GetInt(), 0, 1);
		cvBtShaderBlur = clamp(cv.GetCVar("bt_shader_blur_enable").GetInt(), 0, 1);

		cvBtMultiplier = clamp(cv.GetCVar("bt_multiplier").GetInt(), 0, 20);
		cvBtPlayerMovementMultiplier = clamp(cv.GetCVar("bt_player_movement_multiplier").GetInt(), 1, 20);
		cvBtPlayerWeaponSpeedMultiplier = clamp(cv.GetCVar("bt_player_weapon_speed_multiplier").GetInt(), 1, 20);
		cvBtPlayerModelSlowdown = clamp(cv.GetCVar("bt_player_model_slowdown").GetInt(), 0, 1);

		cvBtDodgeEnable = clamp(cv.GetCVar("bt_dodge_enable").GetInt(), 0, 1);
		cvBtDodgeMultiplier = clamp(cv.GetCVar("bt_dodge_multiplier").GetInt(), 0, 20);
		cvBtDodgePlayerMovementMultiplier = clamp(cv.GetCVar("bt_dodge_player_movement_multiplier").GetInt(), 1, 20);
		cvBtDodgePlayerWeaponSpeedMultiplier = clamp(cv.GetCVar("bt_dodge_player_weapon_speed_multiplier").GetInt(), 1, 20);

		cvBtBerserkEffectEnable = clamp(cv.GetCVar("bt_berserk_effect_enable").GetInt(), 0, 1);
		cvBtBerserkMultiplier = clamp(cv.GetCVar("bt_berserk_multiplier").GetInt(), 0, 20);
		cvBtBerserkPlayerMovementMultiplier = clamp(cv.GetCVar("bt_berserk_player_movement_multiplier").GetInt(), 1, 20);
		cvBtBerserkPlayerWeaponSpeedMultiplier = clamp(cv.GetCVar("bt_berserk_player_weapon_speed_multiplier").GetInt(), 1, 20);
		cvBtBerserkDodgeMultiplier = clamp(cv.GetCVar("bt_berserk_dodge_multiplier").GetInt(), 0, 20);
		cvBtBerserkDodgePlayerMovementMultiplier = clamp(cv.GetCVar("bt_berserk_dodge_player_movement_multiplier").GetInt(), 1, 20);
		cvBtBerserkDodgePlayerWeaponSpeedMultiplier = clamp(cv.GetCVar("bt_berserk_dodge_player_weapon_speed_multiplier").GetInt(), 1, 20);

		cvBtMusicVolume = clamp(cv.GetCVar("bt_music_volume").GetFloat(), 0.0, 1.0);

		cvBtSoundStartType = clamp(cv.GetCVar("bt_sound_start_type").GetInt(), 0, 4);
		cvBtSoundDodgeType = clamp(cv.GetCVar("bt_sound_dodge_type").GetInt(), 0, 1);
		cvBtSoundLoopType = clamp(cv.GetCVar("bt_sound_loop_type").GetInt(), 0, 3);
		cvBtSoundStopType = clamp(cv.GetCVar("bt_sound_stop_type").GetInt(), 0, 4);

		// initialize variables
		btMultiplier = cvBtMultiplier;
		btPlayerMovementMultiplier = cvBtPlayerMovementMultiplier;
		btPlayerWeaponSpeedMultiplier = cvBtPlayerWeaponSpeedMultiplier;
	}

	bool applyMultipliers(bool forceDoSlowGame = false)
	{
		bool doSlowGame = forceDoSlowGame;

		bool stopDodge = btActive && btDodgeActive && cvBtDodgeEnable && BtHelperFunctions.isPlayerSteppingFloor(btPlayerActivator);
		if (btDodgeActive && stopDodge) 
		{
			btDodgeActive = false;
			doSlowGame = true;
		}

		bool isDodge = btActive && (btDodgeActive || (cvBtDodgeEnable && !btDodgeActive && BtHelperFunctions.isPlayerMidAir(btPlayerActivator)));
		if (!btDodgeActive && isDodge)
		{
			Inventory btInv = btPlayerActivator.FindInventory("BtItemData");
			BtItemData btItemData = btInv == NULL
					? NULL
					: BtItemData(btInv);

			if (btItemData != NULL && btItemData.adrenalinePlayerInfo != NULL && btItemData.adrenalinePlayerInfo.playerDodged)
			{
				btDodgeActive = true;
				doSlowGame = true;
				if (cvBtShaderBlur) btBlurEffectCounter = btBlurEffectCounter > 0 ? btBlurEffectCounter : 17;
				btEffectCounter = btEffectCounter == 1 ? 17 : btEffectCounter;

				// play dodge sound
				if (cvBtSoundDodgeType != 0)
				{
					btPlayerActivator.A_StopSound(16); // stops loop sound
					btPlayerActivator.A_StartSound(BtHelperFunctions.getSoundTypeDodge(cvBtSoundDodgeType), 15, CHANF_UI|CHANF_OVERLAP, 1.0, ATTN_NONE, 1.0);
				}
			}
			else
			{
				// player didn't jumped, not enabling dodge
				isDodge = false;
			}
		}

		bool isBerserk = cvBtBerserkEffectEnable && btActive && btBerserkActive;
		doSlowGame = (cvBtDodgeEnable || cvBtBerserkEffectEnable) && doSlowGame && btTic > 0;
		if (doSlowGame)
		{
			slowGame(false, false, true);
		}

		if (cvBtDodgeEnable && isDodge && cvBtBerserkEffectEnable && isBerserk)
		{
			btMultiplier = cvBtBerserkDodgeMultiplier;
			btPlayerMovementMultiplier = cvBtBerserkDodgePlayerMovementMultiplier;
			btPlayerWeaponSpeedMultiplier = cvBtBerserkDodgePlayerWeaponSpeedMultiplier;
		}
		else if (cvBtDodgeEnable && isDodge)
		{
			btMultiplier = cvBtDodgeMultiplier;
			btPlayerMovementMultiplier = cvBtDodgePlayerMovementMultiplier;
			btPlayerWeaponSpeedMultiplier = cvBtDodgePlayerWeaponSpeedMultiplier;
		}
		else if (cvBtBerserkEffectEnable && isBerserk)
		{
			btMultiplier = cvBtBerserkMultiplier;
			btPlayerMovementMultiplier = cvBtBerserkPlayerMovementMultiplier;
			btPlayerWeaponSpeedMultiplier = cvBtBerserkPlayerWeaponSpeedMultiplier; 
		}
		else
		{
			btMultiplier = cvBtMultiplier;
			btPlayerMovementMultiplier = cvBtPlayerMovementMultiplier;
			btPlayerWeaponSpeedMultiplier = cvBtPlayerWeaponSpeedMultiplier;
		}

		postTickController.btMultiplier = btMultiplier;
		postTickController.btPlayerMovementMultiplier = btPlayerMovementMultiplier;
		postTickController.btPlayerWeaponSpeedMultiplier = btPlayerWeaponSpeedMultiplier;

		return doSlowGame;
	}

	/**
	* Checks that player can actually start bullet time and starts it if apply slow is true.
	* When apply slow is false, bullet time stops and resets all actors / sectors velocities, tics.
	*/
	void doSlowTime(bool applySlow, PlayerPawn player)
	{
		if (player == NULL) return;
		bool hasBulletTimeCounter = (player.CheckInventory("BtBerserkerCounter", 1)) || player.CheckInventory("BtAdrenaline", 1) || cvBtAdrenalineUnlimited;

		// starts bullet time
		if (applySlow && (hasBulletTimeCounter || player.pos.z != player.floorz) && player.health > 0)
		{
			btTic = 0;
			btSoundStartCounter = 0;

			initCvarVariables(); // reinitialize cvars
			
			if (cvBtShaderBlur) btBlurEffectCounter = btBlurEffectCounter > 0 ? btBlurEffectCounter : 17;

			int adrenalineAmount = player.CountInv("BtAdrenaline");

			// play bullet time sounds
			if (cvBtSoundStartType != 0)
				player.A_StartSound(BtHelperFunctions.getSoundTypeStart(cvBtSoundStartType),  15, CHANF_UI, 1.0, ATTN_NONE, 1.0);

			postTickController = PostTickDummyController(player.Spawn("PostTickDummyController"));
			postTickController.btMultiplier = btMultiplier;
			postTickController.btPlayerMovementMultiplier = btPlayerMovementMultiplier;
			postTickController.btPlayerWeaponSpeedMultiplier = btPlayerWeaponSpeedMultiplier;
			postTickController.applySlow = true;

			// get music vol cvar value
			float musicVol = clamp(CVar.GetCVar("snd_musicvolume").GetFloat(), 0.0, 1.0);
			float newVolume = musicVol * cvBtMusicVolume;
			SetMusicVolume(newVolume);
			
			btPlayerActivator = player;
			btActive = true;
			if (!cvBtHideMessage) console.printf("Bullet Time!");
		} 
		else if (btActive)
		{ // stops bullet time
			btTic = 0;
			btSoundStartCounter = 0;
			slowGame(false, false, false);
			SetMusicVolume(1);

			if (player) 
			{
				if (cvBtSoundStopType != 0)
					player.A_StartSound(BtHelperFunctions.getSoundTypeStop(cvBtSoundStopType),  15, CHANF_UI, 1.0, ATTN_NONE, 1.0);
				if (cvBtSoundLoopType != 0) player.A_StopSound(16);

				Inventory btInv = player.FindInventory("BtItemData");
				if (btInv != NULL)
				{
					BtItemData btItemData = BtItemData(btInv);
					btItemData.adrenalinePlayerInfo.playerDodged = false;
				}
			}

			postTickController.applySlow = false;
			btPlayerActivator = null;
			btActive = false;
			btDodgeActive = false;
			applyMultipliers();
		}
	}

	/**
	* Checks if player's health went up or down, and gives adrenaline accordingly
	*/
	void handlePlayerAdrenaline(out bool forceDoSlowGame)
	{
		PlayerPawn doomPlayer;
		ThinkerIterator playerList = ThinkerIterator.Create("PlayerPawn", Thinker.STAT_PLAYER);

		while (doomPlayer = PlayerPawn(playerList.Next()) )
		{
			bool isVoodooDoll = BtHelperFunctions.isPlayerPawnVoodooDoll(doomPlayer);
			if (isVoodooDoll) continue;

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

			// enables bullet time when player dodges
			if (btItemData.adrenalinePlayerInfo.playerDodged && !btActive)
			{
				btConsoleActive = true;
				if (btPlayerActivator == null) btPlayerActivator = doomPlayer;
			}

			// gives adrenaline based on player last health and current health
			int newHealth = doomPlayer.health;
			int oldHealth = btItemData.adrenalinePlayerInfo.lastHealth;
			if (newHealth != oldHealth)
			{
				int itemAmount = newHealth < oldHealth 
					? (oldHealth - newHealth) * cvBtAdrenalinePlayerDamageRewardMultiplier : 0;
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
						int berserkerMaxTicEffect = 35 * cvBtBerserkEffectDuration;
						int firstPowerUpTic = powerUp.Args[1];
						int currentPowerUpTic = powerUp.EffectTics;

						if (firstPowerUpTic != 0) 
						{
							int ticDiff = (firstPowerUpTic - currentPowerUpTic);

							if (ticDiff < 0 && currentPowerUpTic <= berserkerMaxTicEffect)
							{
								// forces player adrenaline to be at 100% when berserker counter effect is on
								int counterMultiplier = cvBtBerserkEffectDuration / 5;
								int berserkCounter = (berserkerMaxTicEffect - currentPowerUpTic) * 3 / counterMultiplier;
								
								doomPlayer.GiveInventory("BtAdrenaline", 1000);
								doomPlayer.SetInventory("BtBerserkerCounter", berserkCounter);

								if (cvBtBerserkEffectEnable)
								{
									bool oldBtBerserkActive = btBerserkActive;
									btBerserkActive = (berserkCounter) > 0;

									if (oldBtBerserkActive != btBerserkActive)
									{
										forceDoSlowGame = true;
									}
								}
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

			if (btItemData.adrenalinePlayerInfo.playerJumpTic == 0 && btItemData.adrenalinePlayerInfo.playerDodged && doomPlayer.pos.z == doomPlayer.floorz)
			{
				btItemData.adrenalinePlayerInfo.playerDodged = false;
				btConsoleActive = true;
			}
			else if (btItemData.adrenalinePlayerInfo.playerJumpTic > 0) btItemData.adrenalinePlayerInfo.playerJumpTic--;

			// handle adrenaline regeneration
			int ticDiff = 35 - cvBtAdrenalineRegenSpeed;
			if (!btActive && ticDiff < 35)
			{
				bool doRegenAdrenaline = (btOneSecondTick - cvBtAdrenalineRegenSpeed) < 0;
				if (doRegenAdrenaline) doomPlayer.GiveInventory("BtAdrenaline", 1);
			}
		}
	}

	/**
	* When a player kills a Monster, grants adrenaline based on Monster health and damage done to it
	*/
	void handlePlayerAdrenalineKills()
	{
		PlayerPawn firstPlayer = players.Size() > 0 ? PlayerPawn(players[0].mo) : null;
		
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
				curActor.isDead = true; // monster is dead, do not give more adrenaline points
				if (!curActor.attacker) continue;

				int adrenalineValue = 1 * cvBtAdrenalineKillRewardMultiplier;
				if (curActor.actorRef)
				{
					// grants adrenaline based on damage done
					if (curActor.actorRef.health < -200) 
						adrenalineValue += 5 * cvBtAdrenalineKillRewardMultiplier;
					else if (curActor.actorRef.health < -100) 
						adrenalineValue += 3 * cvBtAdrenalineKillRewardMultiplier;
					else if (curActor.actorRef.health < -50) 
						adrenalineValue += 2 * cvBtAdrenalineKillRewardMultiplier;
					else if (curActor.actorRef.health < -20) 
						adrenalineValue += 1 * cvBtAdrenalineKillRewardMultiplier;

					// adrenaline based on monster health
					adrenalineValue += clamp(sqrt(curActor.startHealth) * cvBtAdrenalineKillRewardMultiplier, 0, 350);
				}

				
				PlayerPawn doomPlayer = curActor.attacker == curActor.actorRef
					? firstPlayer // special case when monster kills itself (ex: in some mods its used by headshots or self damage)
					: PlayerPawn(curActor.attacker);

				if ((cvBtAdrenalineKillRewardWhenActive || !btActive) && doomPlayer) // grant only when bullet time is not enabled
					doomPlayer.GiveInventory("BtAdrenaline", adrenalineValue);

				// second attacker is when a player hits an explosive barrel, and that kills the monster
				if (curActor.secondAttacker) 
				{
					doomPlayer = doomPlayer != NULL ? doomPlayer : PlayerPawn(curActor.secondAttacker);

					string firstClassName = curActor.attacker.GetClassName();
					string lwrFirstClassName = firstClassName.MakeLower();

					if (!btActive && firstClassName && lwrfirstClassName.IndexOf("barrel") != -1 && doomPlayer) {
						doomPlayer.GiveInventory("BtAdrenaline", adrenalineValue);
					}
				}
			}
			else if (curActor.isDead && curActor.actorRef && curActor.actorRef.health > 0)
			{ 
				curActor.isDead = false; // if actor resurrected, change it's status to not dead
			}
		}
	}

	/**
	* Retrieves Actor Item Data for bullet time tracking purposes.
	* If it doesn't exist, creates it, change it's thinker stat num to prevent major perfomance issues and set it to curActor.
	**/
	BtItemData retrieveActorItemData(Actor curActor)
	{
		Inventory btInv = curActor.FindInventory("BtItemData");
		BtItemData btItemData;

		if (btInv) btItemData = BtItemData(btInv);
		else
		{
			btItemData = BtItemData(curActor.GiveInventoryType("BtItemData"));
			btItemData.ChangeStatNum(10);
		}

		return btItemData;
	}

	/**
	* Creates / Updates Monster Info List. Actors that are considered monsters will be added.
	* This actors must have health higher than 0 and can be counted as kills.
	**/
	void updateBtMonsterInfoList(Actor curActor, BtItemData btItemData)
	{
		if (curActor.health > 0 && curActor.bCountKill)
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

	/**
	* Track all Actors of current game. When bt is enabled, they will be slowed down / sped up.
	* Also updates monsterInfoList if needed
	**/
	void trackActors(bool handleSlowActor, bool applySlow, bool doUpdateMonsterInfoList, bool fromMultiplierChange)
	{
		if (btMultiplier == 0 && handleSlowActor)
		{
			if (applySlow && !btPlayerActivator.CheckInventory("BtTimeFreeze", 1)) btPlayerActivator.A_GiveInventory("BtTimeFreeze");
			else if (!applySlow) btPlayerActivator.A_TakeInventory("BtTimeFreeze");

			return;
		}

		Actor curActor;
		ThinkerIterator actorList = ThinkerIterator.Create("Actor", Thinker.STAT_DEFAULT);

		while (curActor = Actor(actorList.Next()))
		{
			bool notStaticActor = curActor.tics > 0 || (curActor.tics == -1 && curActor.vel.Length() > 0);
			if (!notStaticActor) continue;
			BtItemData btItemData = retrieveActorItemData(curActor);
			
			if (btItemData.monsterInfo == NULL && doUpdateMonsterInfoList)
			{
				updateBtMonsterInfoList(curActor, btItemData);
			}

			if (handleSlowActor && !btItemData.whitelisted)
			{
				slowActor(curActor, applySlow, btItemData, fromMultiplierChange);
			}
		}
	}

	void slowGame(bool bulletTime, bool updateMonsterInfoList, bool fromMultiplierChange)
	{
		slowPlayers(bulletTime);

		if (btMultiplier != 1)
		{
			slowLightSectors(bulletTime);
			slowMovingSectors(bulletTime);	
			slowScrollers(bulletTime);
			trackActors(true, bulletTime, updateMonsterInfoList, fromMultiplierChange);
		}
	}

	void slowActor(Actor curActor, bool applySlow, BtItemData btItemData, bool fromMultiplierChange = false)
	{
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
		else if (applySlow && fromMultiplierChange) // when multiplier changes, speed is returned back to normal so we have to change back tics and vel to where it was when bt is on
		{
			btItemData.actorInfo.lastTics /= btMultiplier;
			btItemData.actorInfo.lastVel /= btMultiplier;
			curActor.vel = btItemData.actorInfo.lastVel;

			if (curActor.tics != -1)
				curActor.tics = btItemData.actorInfo.lastTics;
		}
		else if (!createNewActorInfo && applySlow)
		{ // when bt is on, slow down velocity constantly
			double accelZ = abs(curActor.vel.z - btItemData.actorInfo.lastVel.z);
			bool hasExternalForceZ = accelZ > 1.1 && abs(curActor.vel.z) < 32766 && !fromMultiplierChange; // last

			Vector3 lastOgVel = curActor.vel;

			double velX = btItemData.actorInfo.lastVel.x != curActor.vel.x && curActor.vel.x != 0
						? btItemData.actorInfo.lastVel.x + (curActor.vel.x - btItemData.actorInfo.lastVel.x) / btMultiplier
						: curActor.vel.x;
			double velY = btItemData.actorInfo.lastVel.y != curActor.vel.y && curActor.vel.y != 0
						? btItemData.actorInfo.lastVel.y + (curActor.vel.y - btItemData.actorInfo.lastVel.y) / btMultiplier
						: curActor.vel.y;
			double velZ = btItemData.actorInfo.lastVel.z != curActor.vel.z && (curActor.vel.z != 0 || (curActor.floorz != curActor.pos.z && curActor.ceilingz != curActor.pos.z + curActor.height && velX != 0 && velY != 0 && btItemData.actorInfo.lastOgVel.z != 0))
						? btItemData.actorInfo.lastVel.z + (curActor.vel.z - btItemData.actorInfo.lastVel.z) / (btMultiplier * btMultiplier)
						: curActor.vel.z;

			if (hasExternalForceZ) velZ *= btMultiplier;
			if (accelZ > 32766) velZ = 0;

			curActor.vel = (velX, velY, velZ);

			if (btItemData.actorInfo.lastTics == 1 &&
				btItemData.actorInfo.lastState != curActor.CurState &&
				curActor.tics != -1)
			{ // when actor tics reached 1, slow it down by multiply the ticks again (or back to where it was when bt off)
				curActor.tics = (applySlow) ? curActor.tics * btMultiplier : curActor.tics / btMultiplier;
			}

			btItemData.actorInfo.lastOgVel = lastOgVel;
		}

		// Loop through all items to check for powerups
		for (Inventory item = curActor.Inv; item != null; item = item.Inv)
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

		// prevents any actor from reaching tic 0 due to float to int conversion
		if (!applySlow && curActor.tics == 0) curActor.tics = 1;

		// Slow sound pitch
		float soundPitch = applySlow ? BtHelperFunctions.calculateSoundPitch(btMultiplier) : 1.0;
		for (int k = 1; k < 5; k++)
		{
			curActor.A_SoundPitch(k, soundPitch);
		} 
		
		// save data for next tic when bt on
		btItemData.actorInfo.lastState = curActor.CurState;
		btItemData.actorInfo.lastTics = curActor.tics;
		btItemData.actorInfo.lastVel = curActor.vel;

		if (!applySlow && !fromMultiplierChange) btItemData.actorInfo = NULL; // removes actorInfo, so that when reactivating bullet time, it is slowed down again
	}

	void slowPlayers(bool applySlow, bool fromMultiplierChange = false)
	{
		PlayerPawn doomPlayer;
		ThinkerIterator playerList = ThinkerIterator.Create("PlayerPawn", Thinker.STAT_PLAYER);

		// supports -100 to 100 overlays of weapons
		int weaponLayerAmount = 200; // keep in mind when changing the number, also change static number length in BtActorInfo of lastWeaponTics and lastWeaponState
		Array<Int> weaponLayers;
		for (int i = -(int(weaponLayerAmount / 2)); i <= int(weaponLayerAmount / 2) - 1; i++) {
			weaponLayers.Push(i);
		}
		weaponLayers.Push(1000); // for Flash overlay

		while (doomPlayer = PlayerPawn(playerList.Next()) )
		{
			bool isVoodooDoll = BtHelperFunctions.isPlayerPawnVoodooDoll(doomPlayer);
			if (isVoodooDoll) continue;

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
				doomPlayer.speed = applySlow ? doomPlayer.speed / btPlayerMovementMultiplier : btItemData.actorInfo.lastSpeed * btPlayerMovementMultiplier;
				doomPlayer.vel = applySlow ? doomPlayer.vel / btPlayerMovementMultiplier : btItemData.actorInfo.lastVel * btPlayerMovementMultiplier;
				doomPlayer.viewBob = applySlow ? doomPlayer.viewBob / btPlayerMovementMultiplier : doomPlayer.viewBob * btPlayerMovementMultiplier;

				if (doomPlayer.tics != -1 && cvBtPlayerModelSlowdown)
					doomPlayer.tics = applySlow ? doomPlayer.tics * btPlayerWeaponSpeedMultiplier : doomPlayer.tics / btPlayerWeaponSpeedMultiplier;
			}
			else if (applySlow && fromMultiplierChange) // when multiplier changes, speed is returned back to normal so we have to change back tics and vel to where it was when bt is on
			{
				btItemData.actorInfo.lastTics /= btPlayerWeaponSpeedMultiplier;
				if (btMultiplier != 0) btItemData.actorInfo.lastVel /= btMultiplier;
				doomPlayer.vel = btItemData.actorInfo.lastVel;

				if (doomPlayer.tics != -1 && cvBtPlayerModelSlowdown)
					doomPlayer.tics = btItemData.actorInfo.lastTics;
			}
			else if (!createNewPlayerInfo && applySlow)
			{ // check for change in movement speed constantly

				// checks difference between last speed and current speed
				double accelXY = (doomPlayer.vel.x - btItemData.actorInfo.lastVel.x, doomPlayer.vel.y - btItemData.actorInfo.lastVel.y).length();
				double accelZ = abs(doomPlayer.vel.z - btItemData.actorInfo.lastVel.z);

				// when on air nearly all movements will be counted as external force
				float minAcceleration = doomPlayer.vel.z != 0 ? 0.1 : 1.1;

				// a hack here is applied to move 'smoother', because if doomguy gets slowdown ten times,
				// he will slide A LOT. This prevents that. And also checks for external forces (explosion from rocket, etc.)
				if (accelXY > minAcceleration && (btItemData.actorInfo.externalForce == 0 || btItemData.actorInfo.externalForce < accelXY))
					btItemData.actorInfo.externalForce = accelXY;
				else if (accelXY > minAcceleration && btItemData.actorInfo.externalForce > minAcceleration)
					btItemData.actorInfo.externalForce += (accelXY / btPlayerMovementMultiplier);
				else if (accelXY == 0 || btItemData.actorInfo.externalForce < minAcceleration)
					btItemData.actorInfo.externalForce = 0;
				else if (btItemData.actorInfo.externalForce > minAcceleration)
					btItemData.actorInfo.externalForce = btItemData.actorInfo.externalForce - accelXY;

				// when doomguy jumps a second time or when he receives an external velocity, reduce the last one so that
				// the sum on this next one is not too big, otherwise he'll go flying
				bool hasExternalForceZ = accelZ > 1.1; // doomguy received an external force or jumped, its vel z increased
				bool didJump = (btItemData.actorInfo.playerJumpTic == 2 && doomPlayer.vel.z > btItemData.actorInfo.lastVel.z) || (btItemData.actorInfo.playerJumpTic == 1 && doomPlayer.vel.z > 0 && doomPlayer.vel.z > btItemData.actorInfo.lastVel.z);
				if (didJump || hasExternalForceZ)
				{
					if (btPlayerMovementMultiplier != 1) btItemData.actorInfo.lastVel.z /= ((btPlayerMovementMultiplier * btPlayerMovementMultiplier) / 2);
				} 

				int xyMultiplier = btPlayerMovementMultiplier;
				int zMultiplier = btPlayerMovementMultiplier * btPlayerMovementMultiplier;

				// when acceleration is nearly constant, the slowdown will be higher on air (to prevent literal flying)
				if (doomPlayer.vel.z != 0 && accelXY - btItemData.actorInfo.lastAccelXY < 0.01) xyMultiplier *= btPlayerMovementMultiplier;

				Vector3 lastOgVel = doomPlayer.vel;

				double velX = btItemData.actorInfo.lastVel.x != doomPlayer.vel.x && btItemData.actorInfo.externalForce > minAcceleration && doomPlayer.vel.x != 0
							? btItemData.actorInfo.lastVel.x + (doomPlayer.vel.x - btItemData.actorInfo.lastVel.x) / xyMultiplier
							: doomPlayer.vel.x;
				double velY = btItemData.actorInfo.lastVel.y != doomPlayer.vel.y && btItemData.actorInfo.externalForce > minAcceleration && doomPlayer.vel.y != 0
							? btItemData.actorInfo.lastVel.y + (doomPlayer.vel.y - btItemData.actorInfo.lastVel.y) / xyMultiplier
							: doomPlayer.vel.y;
				double velZ = btItemData.actorInfo.lastVel.z != doomPlayer.vel.z && (doomPlayer.vel.z != 0 || (doomPlayer.floorz != doomPlayer.pos.z && doomPlayer.ceilingz != doomPlayer.pos.z + doomPlayer.height && btItemData.actorInfo.lastOgVel.z != 0))
							? btItemData.actorInfo.lastVel.z + (doomPlayer.vel.z - btItemData.actorInfo.lastVel.z) / zMultiplier
							: doomPlayer.vel.z;

				// external forces or jumping shouldn't be that slow on Z
				if ((hasExternalForceZ && btItemData.actorInfo.playerJumpTic == 0) || didJump) 
				{
					velZ *= btPlayerMovementMultiplier;
				}

				// hack: sets velZ to 0 when stepping other actors, but allows velZ when jumping, also constraints velZ below 1000 if a glitch happens to prevent int overflow
				// this hack is done because when we step onto other actors, velZ is always > 0, because we are 'floating' above actors
				bool playerIsSteppingActor = BtHelperFunctions.checkPlayerIsSteppingActor(doomPlayer); 
				if ((playerIsSteppingActor && int(accelZ) != int(doomPlayer.jumpZ)) || accelZ > 1000)  velZ = 0;

				doomPlayer.vel = (velX, velY, velZ);

				// slows down speed as well, this is constant velocity
				double newSpeed = btItemData.actorInfo.lastSpeed != doomPlayer.speed
								? doomPlayer.speed / btPlayerMovementMultiplier
								: doomPlayer.speed;

				doomPlayer.speed = newSpeed;

				// when actor tics reached 1, slow it down by multiply the ticks again (or back to where it was when bt off)
				if (btItemData.actorInfo.lastTics == 1 &&
					btItemData.actorInfo.lastState != doomPlayer.CurState &&
					doomPlayer.tics != -1 &&
					cvBtPlayerModelSlowdown)
				{ 
					doomPlayer.tics = (applySlow) ? doomPlayer.tics * btPlayerWeaponSpeedMultiplier : doomPlayer.tics / btPlayerWeaponSpeedMultiplier;
				}

				btItemData.actorInfo.lastAccelXY = accelXY;
				btItemData.actorInfo.lastOgVel = lastOgVel;
			}

			// Loop through all items to check for powerups
			for (Inventory item = doomPlayer.Inv; item != null; item = item.Inv)
			{
				if (btMultiplier == 0) continue;

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
			for (int j = 0; j < weaponLayers.Size(); j++)
			{
				PSprite playerWp = doomPlayer.Player.FindPSprite(weaponLayers[j]);
				if (playerWp)
				{
					if (applySlow && fromMultiplierChange)
					{
						btItemData.actorInfo.lastWeaponTics[j] /= btPlayerWeaponSpeedMultiplier;
						playerWp.tics = btItemData.actorInfo.lastWeaponTics[j];
					}

					bool slowTicPlayer = (btItemData.actorInfo.lastWeaponTics[j] == 1 || 
										  createNewPlayerInfo || 
										  playerWp.CurState != btItemData.actorInfo.lastWeaponState[j]) 
										  ? true : false;
					if (slowTicPlayer || !applySlow)
					{
						playerWp.tics = (applySlow) ? playerWp.tics * btPlayerWeaponSpeedMultiplier : playerWp.tics / btPlayerWeaponSpeedMultiplier;
						if (playerWp.tics < 1 || (playerWp.CurState == null && btItemData.actorInfo.lastWeaponState[j] != null)) {
							playerWp.tics = 1;
							playerWp.SetState(btItemData.actorInfo.lastWeaponState[j]); // prevents crash when curState is null.
						}// set tics > 0 to prevent state getting stuck / frozen
					}
					btItemData.actorInfo.lastWeaponState[j] = playerWp.CurState;
					btItemData.actorInfo.lastWeaponTics[j] = playerWp.tics;
				}
			}

			// slow or restore all player sounds
			float soundPitch = applySlow ? BtHelperFunctions.calculateSoundPitch(btPlayerWeaponSpeedMultiplier) : 1.0;
			for (int k = 0; k < 8; k++)
				doomPlayer.A_SoundPitch(k, soundPitch);
			
			// change current floor/last floor damage interval
			if (btMultiplier != 0 && !btItemData.actorInfo.lastSector)
			{
				btItemData.actorInfo.lastSector = doomPlayer.CurSector;
				doomPlayer.CurSector.damageinterval = applySlow 
					? doomPlayer.CurSector.damageinterval * btMultiplier 
					: doomPlayer.CurSector.damageinterval;
			}
			else if (btMultiplier != 0 && ((btItemData.actorInfo.lastSector && btItemData.actorInfo.lastSector != doomPlayer.CurSector) || !applySlow))
			{
				btItemData.actorInfo.lastSector.damageinterval /= btMultiplier;
				btItemData.actorInfo.lastSector = doomPlayer.CurSector;
				doomPlayer.CurSector.damageinterval = applySlow 
					? doomPlayer.CurSector.damageinterval * btMultiplier
					: doomPlayer.CurSector.damageinterval;
			}

			btItemData.actorInfo.lastState = doomPlayer.CurState;
			btItemData.actorInfo.lastTics = doomPlayer.tics;
			btItemData.actorInfo.lastVel = doomPlayer.vel;
			btItemData.actorInfo.lastSpeed = doomPlayer.speed;
			btItemData.actorInfo.lastSector = doomplayer.CurSector;
			btItemData.actorInfo.playerJumpTic = btItemData.actorInfo.playerJumpTic > 0 ? btItemData.actorInfo.playerJumpTic - 1 : 0; // resets playerDodged check

			if (!applySlow && !fromMultiplierChange) btItemData.actorInfo = NULL; // removes actorInfo, so that when reactivating bullet time, it is slowed down again
		}
	}

	void slowLightSectors(bool applySlow)
	{
		int thinkerType = (applySlow && btTic == 1) ? Thinker.STAT_LIGHT : (!applySlow || btTic >= btMultiplier) ? Thinker.STAT_STATIC : -1;
		int changedThinkerType = (applySlow && btTic == 1) ? Thinker.STAT_STATIC : (!applySlow || (btTic >= btMultiplier && btMultiplier != 0)) ? Thinker.STAT_LIGHT : -1;

		if (thinkerType != -1 && changedThinkerType != -1)
		{
			Thinker lightThinker;
			ThinkerIterator thinkerList = ThinkerIterator.Create("Lighting", thinkerType);
			while (lightThinker = Thinker(thinkerList.Next()) )
			{
				lightThinker.changeStatNum(changedThinkerType);
			}
		}
	}

	void slowScrollers(bool applySlow)
	{
		int thinkerType = (applySlow && btTic == 1) ? Thinker.STAT_SCROLLER : (!applySlow || btTic >= btMultiplier) ? Thinker.STAT_STATIC : -1;
		int changedThinkerType = (applySlow && btTic == 1) ? Thinker.STAT_STATIC : (!applySlow || (btTic >= btMultiplier && btMultiplier != 0)) ? Thinker.STAT_SCROLLER : -1;

		if (thinkerType != -1 && changedThinkerType != -1)
		{
			Thinker scrollerThinker;
			ThinkerIterator thinkerList = ThinkerIterator.Create("Object", thinkerType);
			while (scrollerThinker = Thinker(thinkerList.Next()) )
			{
				string thinkerClassName = scrollerThinker.GetClassName();
				if (thinkerClassName == "Scroller")
				{
					scrollerThinker.changeStatNum(changedThinkerType);
				}
			}
		}
	}

	void slowMovingSectors(bool applySlow)
	{
		bool anyBtIsFreeze = cvBtMultiplier == 0 || cvBtBerserkMultiplier == 0 || cvBtDodgeMultiplier == 0 || cvBtBerserkDodgeMultiplier == 0;

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
			if (!btActive || (!applySlow && anyBtIsFreeze))
			{
				sectorInfoList[j].thinkerRef.changeStatNum(Thinker.STAT_SECTOREFFECT); // enables sector to move again
			}

			if (btMultiplier == 0) continue; // in freeze mode, no need to move sectors

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
		
		if (!btActive || (!applySlow && anyBtIsFreeze))
		{
			sectorInfoList.Clear();
		}

		postTickController.sectorInfoList.Move(sectorInfoList); // update values for post tick array
	}
}