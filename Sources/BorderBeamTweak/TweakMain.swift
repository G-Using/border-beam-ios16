//
//  TweakMain.swift
//  BorderBeamTweak
//
//  Entry point, called from the C constructor in Entry.c.
//
import UIKit

@_cdecl("borderBeam_init")
public func borderBeam_init() {
    NSLog("[BorderBeam] dylib loaded (v1.1.1, CoreAnimation renderer)")
    BeamHook.install()
}
