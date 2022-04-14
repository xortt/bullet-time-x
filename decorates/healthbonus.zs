ACTOR BtHealthBonus : CustomInventory replaces HealthBonus
{
    +COUNTITEM
    +INVENTORY.ALWAYSPICKUP
    Inventory.PickupMessage "$GOTHTHBONUS" // "Picked up a health bonus."
    States
    {
        Spawn:
            BON1 ABCDCB 6
            Loop
        Pickup:
            TNT1 A 0 A_GiveInventory("BtAdrenaline", 30)
            TNT1 A 0 A_GiveInventory("HealthBonus")
            Stop
    }
}