package meta;

import flixel.FlxG;
import flixel.FlxBasic;
import flixel.FlxSprite;
import flixel.FlxSubState;
import flixel.addons.transition.FlxTransitionableState;
import flixel.math.FlxRect;
import flixel.util.FlxTimer;
import meta.*;
import meta.data.*;
import meta.data.Conductor.BPMChangeEvent;
import meta.data.dependency.FNFUIState;
#if mobile
import mobile.MobileControls;
import mobile.flixel.FlxVirtualPad;
import flixel.FlxCamera;
import flixel.input.actions.FlxActionInput;
import flixel.util.FlxDestroyUtil;
#end

/* 
	Music beat state happens to be the first thing on my list of things to add, it just so happens to be the backbone of
	most of the project in its entirety. It handles a couple of functions that have to do with actual music and songs and such.

	I'm not going to change any of this because I don't truly understand how songplaying works, 
	I mostly just wanted to rewrite the actual gameplay side of things.
 */
class MusicBeatState extends FNFUIState
{
	// original variables extended from original game source
	private var lastBeat:Float = 0;
	private var lastStep:Float = 0;

	public var curStep:Int = 0;
	public var curBeat:Int = 0;

	private var controls(get, never):Controls;

	inline function get_controls():Controls
		return PlayerSettings.player1.controls;

	#if mobile
		var mobileControls:MobileControls;
		var virtualPad:FlxVirtualPad;
		var trackedInputsMobileControls:Array<FlxActionInput> = [];
		var trackedInputsVirtualPad:Array<FlxActionInput> = [];

		public function addVirtualPad(DPad:FlxDPadMode, Action:FlxActionMode)
		{
		    if (virtualPad != null)
			removeVirtualPad();

			virtualPad = new FlxVirtualPad(DPad, Action);
		    add(virtualPad);

			controls.setVirtualPadUI(virtualPad, DPad, Action);
			trackedInputsVirtualPad = controls.trackedInputsUI;
			controls.trackedInputsUI = [];
		}

		public function removeVirtualPad()
		{
			if (trackedInputsVirtualPad.length > 0)
			controls.removeVirtualControlsInput(trackedInputsVirtualPad);

			if (virtualPad != null)
			remove(virtualPad);
		}

		public function addMobileControls(DefaultDrawTarget:Bool = true)
		{
			if (mobileControls != null)
			removeMobileControls();

			mobileControls = new MobileControls();

			switch (MobileControls.mode)
			{
				case 'Pad-Right' | 'Pad-Left' | 'Pad-Custom':
				controls.setVirtualPadNOTES(mobileControls.virtualPad, RIGHT_FULL, NONE);
				case 'Pad-Duo':
				controls.setVirtualPadNOTES(mobileControls.virtualPad, BOTH_FULL, NONE);
				case 'Hitbox':
				controls.setHitBox(mobileControls.hitbox);
				case 'Keyboard': // do nothing
			}

			trackedInputsMobileControls = controls.trackedInputsNOTES;
			controls.trackedInputsNOTES = [];

			var camControls:FlxCamera = new FlxCamera();
			FlxG.cameras.add(camControls, DefaultDrawTarget);
			camControls.bgColor.alpha = 0;

			mobileControls.cameras = [camControls];
			mobileControls.visible = false;
			add(mobileControls);
		}

		public function removeMobileControls()
		{
			if (trackedInputsMobileControls.length > 0)
			controls.removeVirtualControlsInput(trackedInputsMobileControls);

			if (mobileControls != null)
			remove(mobileControls);
		}

		public function addVirtualPadCamera(DefaultDrawTarget:Bool = true)
		{
			if (virtualPad != null)
			{
				var camControls:FlxCamera = new FlxCamera();
				FlxG.cameras.add(camControls, DefaultDrawTarget);
				camControls.bgColor.alpha = 0;
				virtualPad.cameras = [camControls];
			}
		}
		#end

		override function destroy()
		{
			#if mobile
			if (trackedInputsMobileControls.length > 0)
			controls.removeVirtualControlsInput(trackedInputsMobileControls);

			if (trackedInputsVirtualPad.length > 0)
			controls.removeVirtualControlsInput(trackedInputsVirtualPad);
			#end

			super.destroy();

			#if mobile
			if (virtualPad != null)
			virtualPad = FlxDestroyUtil.destroy(virtualPad);

			if (mobileControls != null)
			mobileControls = FlxDestroyUtil.destroy(mobileControls);
			#end
		}
	
	// class create event
	override function create()
	{
		// dump
		Paths.clearStoredMemory();
		if ((!Std.isOfType(this, meta.state.PlayState)) && (!Std.isOfType(this, meta.state.editors.ChartingState)))
			Paths.clearUnusedMemory();
		
		if (transIn != null)
			trace('reg ' + transIn.region);
		
		super.create();
		
		// For debugging
		FlxG.watch.add(Conductor, "songPosition");
		FlxG.watch.add(this, "curBeat");
		FlxG.watch.add(this, "curStep");
	}

	// class 'step' event
	override function update(elapsed:Float)
	{
		updateContents();

		super.update(elapsed);
	}
	
	public function updateContents()
	{
		updateCurStep();
		updateBeat();

		// delta time bullshit
		var trueStep:Int = curStep;
		for (i in storedSteps)
			if (i < oldStep)
				storedSteps.remove(i);
		for (i in oldStep...trueStep)
		{
			if (!storedSteps.contains(i) && i > 0)
			{
				curStep = i;
				stepHit();
				skippedSteps.push(i);
			}
		}
		if (skippedSteps.length > 0)
		{
			trace('skipped steps $skippedSteps');
			skippedSteps = [];
		}
		curStep = trueStep;

		//
		if (oldStep != curStep && curStep > 0 && !storedSteps.contains(curStep))
			stepHit();
		oldStep = curStep;
	}
	
	var oldStep:Int = 0;
	var storedSteps:Array<Int> = [];
	var skippedSteps:Array<Int> = [];
	
	public function updateBeat():Void
	{
		curBeat = Math.floor(curStep / 4);
	}
	
	public function updateCurStep():Void
	{
		var lastChange:BPMChangeEvent = {
			stepTime: 0,
			songTime: 0,
			bpm: 0
		}
		for (i in 0...Conductor.bpmChangeMap.length)
		{
			if (Conductor.songPosition >= Conductor.bpmChangeMap[i].songTime)
				lastChange = Conductor.bpmChangeMap[i];
		}

		curStep = lastChange.stepTime + Math.floor((Conductor.songPosition - lastChange.songTime) / Conductor.stepCrochet);
	}
	
	public function stepHit():Void
	{
		if (curStep % 4 == 0)
			beatHit();

		// trace('step $curStep');

		if (!storedSteps.contains(curStep))
			storedSteps.push(curStep);
		else
			trace('SOMETHING WENT WRONG??? STEP REPEATED $curStep');
	}
	
	public function beatHit():Void
	{
		// used for updates when beats are hit in classes that extend this one
	}
	
	override function add(Object:FlxBasic):FlxBasic
	{
		Main.checkAntialiasing(Object);
		return super.add(Object);
	}
}

class MusicBeatSubState extends FlxSubState
{
	public function new()
	{
		super();
	}

	private var lastBeat:Float = 0;
	private var lastStep:Float = 0;

	private var curStep:Int = 0;
	private var curBeat:Int = 0;
	private var controls(get, never):Controls;

	inline function get_controls():Controls
		return PlayerSettings.player1.controls;

	override function update(elapsed:Float)
	{
		// everyStep();
		var oldStep:Int = curStep;

		updateCurStep();
		curBeat = Math.floor(curStep / 4);

		if (oldStep != curStep && curStep > 0)
			stepHit();

		super.update(elapsed);
	}

	private function updateCurStep():Void
	{
		var lastChange:BPMChangeEvent = {
			stepTime: 0,
			songTime: 0,
			bpm: 0
		}
		for (i in 0...Conductor.bpmChangeMap.length)
		{
			if (Conductor.songPosition > Conductor.bpmChangeMap[i].songTime)
				lastChange = Conductor.bpmChangeMap[i];
		}

		curStep = lastChange.stepTime + Math.floor((Conductor.songPosition - lastChange.songTime) / Conductor.stepCrochet);
	}

	public function stepHit():Void
	{
		if (curStep % 4 == 0)
			beatHit();
	}

	public function beatHit():Void
	{
		// do literally nothing dumbass
	}
	
	override function add(Object:FlxBasic):FlxBasic
	{
		Main.checkAntialiasing(Object);
		return super.add(Object);
	}
}
