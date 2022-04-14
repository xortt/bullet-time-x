class BtHelperFunctions
{
    static bool checkPlayerIsSteppingActor(PlayerPawn doomPlayer)
    {
        // check if any actor is below player's radius to prevent glitching when calculating Z slowdown.
        BlockThingsIterator bti = BlockThingsIterator.Create(doomPlayer);
        Actor mo;
        bool playerIsSteppingActor = false;

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

                playerIsSteppingActor = playerInRect && doomPlayer.pos.z == mo.pos.z + mo.height;
                if (playerIsSteppingActor) 
                {
                    break; // player is stepping a monster / blockable
                }
            }
        }

        return playerIsSteppingActor;
    }
}