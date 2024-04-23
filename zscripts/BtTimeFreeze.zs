//===========================================================================
//
// TimeFreezer
// This is the same as the og TimeFreezer the only exception is that it doesn't have a
// duration and sounds are allowed.
//===========================================================================

class BtTimeFreeze : Powerup
{	
    Default
	{
		Powerup.Duration 0x7FFFFFFD; // pretty much infinite
	}
	//===========================================================================
	//
	// InitEffect
	//
	//===========================================================================

	override void InitEffect()
	{
		int freezemask;

		Super.InitEffect();

		if (Owner == null || Owner.player == null)
			return;

		// Give the player and his teammates the power to move when time is frozen.
		freezemask = 1 << Owner.PlayerNumber();
		Owner.player.timefreezer |= freezemask;
		for (int i = 0; i < MAXPLAYERS; i++)
		{
			if (playeringame[i] &&
				players[i].mo != null &&
				players[i].mo.IsTeammate(Owner)
			   )
			{
				players[i].timefreezer |= freezemask;
			}
		}

		// [RH] The effect ends one tic after the counter hits zero, so make
		// sure we start at an odd count.
		EffectTics += !(EffectTics & 1);
		if ((EffectTics & 1) == 0)
		{
			EffectTics++;
		}
		// Make sure the effect starts and ends on an even tic.
		if ((Level.maptime & 1) == 0)
		{
			Level.SetFrozen(true);
		}
		else
		{
			// Compensate for skipped tic, but beware of overflow.
			if(EffectTics < 0x7fffffff)
				EffectTics++;
		}
	}

	//===========================================================================
	//
	// APowerTimeFreezer :: DoEffect
	//
	//===========================================================================

	override void DoEffect()
	{
		Super.DoEffect();
		// [RH] Do not change LEVEL_FROZEN on odd tics, or the Revenant's tracer
		// will get thrown off.
		// [ED850] Don't change it if the player is predicted either.
		if (Level.maptime & 1 || (Owner != null && Owner.player != null && Owner.player.cheats & CF_PREDICTING))
		{
			return;
		}
		// [RH] The "blinking" can't check against EffectTics exactly or it will
		// never happen, because InitEffect ensures that EffectTics will always
		// be odd when Level.maptime is even.
		Level.SetFrozen ( EffectTics > 4*32 
			|| (( EffectTics > 3*32 && EffectTics <= 4*32 ) && ((EffectTics + 1) & 15) != 0 )
			|| (( EffectTics > 2*32 && EffectTics <= 3*32 ) && ((EffectTics + 1) & 7) != 0 )
			|| (( EffectTics >   32 && EffectTics <= 2*32 ) && ((EffectTics + 1) & 3) != 0 )
			|| (( EffectTics >    0 && EffectTics <= 1*32 ) && ((EffectTics + 1) & 1) != 0 ));
	}

	//===========================================================================
	//
	// APowerTimeFreezer :: EndEffect
	//
	//===========================================================================

	override void EndEffect()
	{
		Super.EndEffect();

		// If there is an owner, remove the timefreeze flag corresponding to
		// her from all players.
		if (Owner != null && Owner.player != null)
		{
			int freezemask = ~(1 << Owner.PlayerNumber());
			for (int i = 0; i < MAXPLAYERS; ++i)
			{
				players[i].timefreezer &= freezemask;
			}
		}

		// Are there any players who still have timefreezer bits set?
		for (int i = 0; i < MAXPLAYERS; ++i)
		{
			if (playeringame[i] && players[i].timefreezer != 0)
			{
				return;
			}
		}

		// No, so allow other actors to move about freely once again.
		Level.SetFrozen(false);
	}
}