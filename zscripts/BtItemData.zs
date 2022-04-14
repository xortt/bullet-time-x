/*
	This class is only used to give the Actor an unique id.
	We cannot use Args or TID, because other mods might use them.
	So we give each actor, an inventory item of this type, and get the ids and custom values from here.
*/
class BtItemData : Inventory 
{
	BtActorInfo actorInfo;
	BtActorInfo adrenalinePlayerInfo;
    
	BtMonsterInfo monsterInfo;
	// int btActorId; // when bullet time is on, actor id
	// int normalActorId; // global actor id (not bullet time)
}