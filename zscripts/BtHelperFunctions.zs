class BtHelperFunctions play
{
    enum BtSoundTypes 
    {
        NONE = 0,
        MAX_PAYNE = 1,
        MAX_PAYNE_3 = 2,
        FEAR = 3,
        GTA_V = 4
    }

    enum BtSoundLoopTypes
    {
        LOOP_NONE = 0,
        LOOP_MAX_PAYNE = 1,
        LOOP_MAX_PAYNE_3 = 2,
        LOOP_GTA_V = 3
    }

    enum BtSoundDodgeTypes
    {
        DODGE_NONE = 0,
        DODGE_MAX_PAYNE_3 = 1
    }
    
    static bool checkPlayerIsSteppingActor(PlayerPawn doomPlayer)
    {
        // check if any actor is below player's radius to prevent glitching when calculating Z slowdown.
        BlockThingsIterator bti = BlockThingsIterator.Create(doomPlayer);
        Actor mo;

        while (bti.Next())
        {
            mo = bti.thing;
            if (mo && mo != doomPlayer && mo.bSolid)
            {
                Vector2 rectTopR = ((mo.radius + doomPlayer.radius * 2) * cos(45), (mo.radius + doomPlayer.radius * 2) * sin(45));
                Vector2 rectBotL = ((mo.radius + doomPlayer.radius * 2) * cos(-135), (mo.radius + doomPlayer.radius * 2) * sin(-135));

                Vector2 rectTopPosR = (mo.pos.x + rectTopR.x, mo.pos.y + rectTopR.y);
                Vector2 rectBotPosL = (mo.pos.x + rectBotL.x, mo.pos.y + rectBotL.y);

                double x = doomPlayer.pos.x;
                double y = doomPlayer.pos.y;
                double x1 = rectBotPosL.x;
                double y1 = rectBotPosL.y;
                double x2 = rectTopPosR.x;
                double y2 = rectTopPosR.y;
                bool playerInRect = (x > x1 && x < x2 && y > y1 && y < y2);

                if (playerInRect && doomPlayer.pos.z == mo.pos.z + mo.height) 
                {
                    return true; // player is stepping a monster / blockable
                }
            }
        }

        return false;
    }

    /* Goes through all players list verifying that given PlayerPawn is present in the list.
        If it is not present then it's a voodoo doll.
    */
    static bool isPlayerPawnVoodooDoll(PlayerPawn curPlayer)
    {
        for (int i = 0; i < players.Size(); i++)
        {
            if (curPlayer == players[i].mo) return false;
        }
        return true;
    }

    static bool isPlayerMidAir(PlayerPawn curPlayer)
    {
        int diff = abs(curPlayer.pos.z - curPlayer.floorz);
        return diff > 2; 
    }

    static bool isPlayerSteppingFloor(PlayerPawn curPlayer)
    {
        return curPlayer.floorz == curPlayer.pos.z;
    }

    static float calculateSoundPitch(int multiplier)
    {
        float newMultiplier = Sqrt(multiplier);
        float newPitch = 1 / newMultiplier;
        return clamp(newPitch, 0.3, 1.0);
    }

    static void whitelistBtActor(Actor curActor)
    {
        Inventory btInv = curActor.FindInventory("BtItemData");
        BtItemData btItemData;

        if (btInv) 
        {
            btItemData = BtItemData(btInv);
        } 
        else 
        {
			btItemData = BtItemData(curActor.GiveInventoryType("BtItemData"));
			btItemData.ChangeStatNum(10);
        }
        btItemData.whitelisted = true;
    }

    static string getSoundTypeStart(BtSoundTypes type)
    {
        switch (type) 
        {
            case NONE:
                return "";
            case MAX_PAYNE:
                return "SLWSTART";
            case MAX_PAYNE_3:
                return "MP3START";
            case FEAR:
                return "FRSTART";
            case GTA_V:
                return "GTASTART";
            default:
                return "SLWSTART";
        }
    }

    static string getSoundTypeStop(BtSoundTypes type)
    {
        switch (type) 
        {
            case NONE:
                return "";
            case MAX_PAYNE:
                return "SLWSTOP";
            case MAX_PAYNE_3:
                return "MP3STOP";
            case FEAR:
                return "FRSTOP";
            case GTA_V:
                return "GTASTOP";
            default:
                return "SLWSTOP";
        }
    }

    static string getSoundTypeDodge(BtSoundDodgeTypes type)
    {
        switch (type) 
        {
            case DODGE_NONE:
                return "";
            case DODGE_MAX_PAYNE_3:
                return "MP3DODGE";
            default:
                return "MP3DODGE";
        }
    }

    static string getSoundTypeLoop(BtSoundLoopTypes type, float curAmount, int btMaxDuration)
    {  
        int percentage = (curAmount / 525) * 100;
        int loopPos = 0;

        switch (type) 
        {
            case LOOP_NONE:
                return "";
            case LOOP_MAX_PAYNE:
                return "SLWLOOP";
            case LOOP_MAX_PAYNE_3: 
            {
                if (percentage >= 40) loopPos = 1;
                else if (percentage >= 15) loopPos = 2;
                else loopPos = 3;

                return "MP3LOOP"..loopPos;
            }
            case LOOP_GTA_V:
            {
                if (percentage >= 50) loopPos = 1;
                else if (percentage >= 16) loopPos = 2;
                else if (btMaxDuration >= 30) loopPos = 3;
                else if (btMaxDuration >= 45) loopPos = 4;

                return "GTALOOP"..loopPos;
            }
            default:
                return "SLWLOOP";
        }
    }
}