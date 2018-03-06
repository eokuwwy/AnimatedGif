//  Converted to Swift 4 by Swiftify v4.1.6632 - https://objectivec2swift.com/
//
//  AnimatedGifView.m
//  AnimatedGif
//
//  Created by Marco Köhler on 09.11.15.
//  Copyright (c) 2015 Marco Köhler. All rights reserved.
//
import GLUT
import ScreenSaver

let LOAD_BTN = 0
let UNLOAD_BTN = 1
let VIEW_OPT_STRETCH_OPTIMAL = 0
let VIEW_OPT_STRETCH_MAXIMAL = 1
let VIEW_OPT_KEEP_ORIG_SIZE = 2
let VIEW_OPT_STRETCH_SMALL_SIDE = 3
let MAX_VIEW_OPT = 3
let SYNC_TO_VERTICAL = 1
let DONT_SYNC = 0
let FRAME_COUNT_NOT_USED = -1
let FIRST_FRAME = 0
let DEFAULT_ANIME_TIME_INTER = 1 / 15.0
let GL_ALPHA_OPAQUE = 1.0
let NS_ALPHA_OPAQUE = 1.0

class AnimatedGifView : ScreenSaverView {
    var glView: NSOpenGLView?
    @IBOutlet var optionsPanel: NSPanel!
    @IBOutlet var textFieldFileUrl: NSTextField!
    @IBOutlet var checkButtonLoadIntoMem: NSButton!
    @IBOutlet var colorWellBackgrColor: NSColorWell!
    @IBOutlet var segmentButtonLaunchAgent: NSSegmentedControl!
    @IBOutlet var popupButtonViewOptions: NSPopUpButton!
    @IBOutlet var labelVersion: NSTextField!
    @IBOutlet var sliderChangeInterval: NSSlider!
    @IBOutlet var labelChangeInterval: NSTextField!
    @IBOutlet var labelChIntT1: NSTextField!
    @IBOutlet var labelChIntT2: NSTextField!
    @IBOutlet var labelChIntT3: NSTextField!
    @IBOutlet var labelChIntT4: NSTextField!
    @IBOutlet var sliderFpsManual: NSSlider!
    @IBOutlet var labelFpsManual: NSTextField!
    @IBOutlet var labelFpsGif: NSTextField!
    @IBOutlet var checkButtonSetFpsManual: NSButton!
    @IBOutlet var labelFpsT1: NSTextField!
    @IBOutlet var labelFpsT2: NSTextField!
    @IBOutlet var labelFpsT3: NSTextField!
    @IBOutlet var labelFpsT4: NSTextField!
    @IBOutlet var labelFpsT5: NSTextField!
    @IBOutlet var labelFpsT6: NSTextField!

    // keep track of whether or not drawRect: should erase the background
    var animationImages = [AnyHashable]()
    var currFrameCount: Int = 0
    var maxFrameCount: Int = 0
    var img: NSImage?
    var gifRep: NSBitmapImageRep?
    var backgrRed: Float = 0.0
    var backgrGreen: Float = 0.0
    var backgrBlue: Float = 0.0
    var loadAnimationToMem = false
    var trigByTimer = false
    var screenRect = NSRect()
    var targetRect = NSRect()

    override init?(frame: NSRect, isPreview: Bool) {
        trigByTimer = false
        currFrameCount = FRAME_COUNT_NOT_USED
        super.init(frame: frame, isPreview: isPreview)
            // initialize screensaver defaults with an default value
        let defaults = ScreenSaverDefaults(forModuleWithName: (Bundle(for: AnimatedGifView.self).bundleIdentifier) ?? "")
        defaults?.register(defaults: [
        "GifFileName" : "file:///please/select/an/gif/animation.gif",
        "GifFrameRate" : "30.0",
        "GifFrameRateManual" : "NO",
        "ViewOpt" : "0",
        "BackgrRed" : "0.0",
        "BackgrGreen" : "0.0",
        "BackgrBlue" : "0.0",
        "LoadAniToMem" : "NO",
        "ChangeInterval" : "5"
    ])
        
        glView = createGLView()
        animationTimeInterval = DEFAULT_ANIME_TIME_INTER
    
            // get the program arguments of the process
        let args = ProcessInfo.processInfo.arguments
        // check if process was startet with argument -window for window mode of screensaver
        if (args.count == 2) && (args[1] == "-window") {
                // Workaround: disable clock before start, since this leads to a crash with option "-window" of ScreenSaverEngine
            let cmdstr = "\("defaults -currentHost write com.apple.screensaver showClock -bool NO")"
            self.system(cmdstr)
        }
    }
    
    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func system(_ command: String) {
        var args = command.components(separatedBy: " ")
        let path = args.first
        args.remove(at: 0)
        
        let task = Process()
        task.launchPath = path
        task.arguments = args
        task.launch()
        task.waitUntilExit()
    }

    func createGLView() -> NSOpenGLView {
        let attribs:[NSOpenGLPixelFormatAttribute] = [NSOpenGLPixelFormatAttribute(NSOpenGLPFADoubleBuffer), NSOpenGLPixelFormatAttribute(NSOpenGLPFAAccelerated), NSOpenGLPixelFormatAttribute(0)]
        let format = NSOpenGLPixelFormat(attributes: attribs)
        let glview = NSOpenGLView(frame: NSZeroRect, pixelFormat: format)
        var swapInterval: GLint = GLint(SYNC_TO_VERTICAL)
        glview?.openGLContext?.setValues(&swapInterval, for: .swapInterval)
        return glview ?? NSOpenGLView()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        glView?.setFrameSize(newSize)
    }

    func isOpaque() -> Bool {
        // this keeps Cocoa from unnecessarily redrawing our superview
        return true
    }

    deinit {
        glView?.removeFromSuperview()
        glView = nil
    }

    @objc func timerMethod() {
        // after change timer is running out this method is called
        // the animation of last GIF is stopped an memory cleaned, but without destroying GL view or telling the screensaver engine about it (no call of super method; handled by trigByTimer=TRUE)
        trigByTimer = true
        stopAnimation()
        // the animation is start again witch randomly pics a new GIF from folder and start the change timer again, but without telling the screensaver engine about it (no call of super method; handled by trigByTimer=TRUE)
        startAnimation()
        trigByTimer = false
    }

    override func startAnimation() {
        if trigByTimer == false {
            // only call super method in case startAnimation is not called by timerMethod
            super.startAnimation()
            // add glview to screensaver view in case of not in preview mode
            if isPreview == false {
                addSubview(glView!)
            }
            // bug of OSX: since 10.13 the background mode of screensaver is brocken (the ScreenSaverEngine uses for background-mode its own space that is in foreground and this space can't be accessed from the ScreenSaverView)
            // workaround: AnimatedGif use the window-mode of the ScreenSaverEngine and change the behavior of that window to an background window
            if isPreview == false {
                    // get the program arguments of the process
                let args = ProcessInfo.processInfo.arguments
                // check if process was startet with argument -window for window mode of screensaver
                if (args.count == 2) && (args[1] == "-window") {
                    // now we move the window to background level and maximize it as we need it
                    if let aFrame = NSScreen.main?.frame {
                        window?.setFrame(aFrame, display: true)
                    }
                    super.frame = (NSScreen.main?.frame)!
                    window?.styleMask.insert(.fullSizeContentView)
                    window?.collectionBehavior = [.stationary, .canJoinAllSpaces]
                    window.level = kCGDesktopWindowLevel
                }
            }
            if isPreview == false {
                // hide window since next steps need some time an look ugly
                window?.orderOut(self)
            }
        }
            // get filename from screensaver defaults
        let defaults = ScreenSaverDefaults(forModuleWithName: (Bundle(for: AnimatedGifView.self).bundleIdentifier) ?? "")
        let gifFileName = defaults?.string(forKey: "GifFileName")
        let frameRate: Float? = defaults?.float(forKey: "GifFrameRate")
        let frameRateManual: Bool? = defaults?.bool(forKey: "GifFrameRateManual")
        loadAnimationToMem = (defaults?.bool(forKey: "LoadAniToMem"))!
        let viewOption: Int? = defaults?.integer(forKey: "ViewOpt")
        backgrRed = (defaults?.float(forKey: "BackgrRed"))!
        backgrGreen = (defaults?.float(forKey: "BackgrGreen"))!
        backgrBlue = (defaults?.float(forKey: "BackgrBlue"))!
        let changeIntervalInSec: Int = (defaults?.integer(forKey: "ChangeInterval"))! * 15
            // select a random file from directory or keep the file if it was already a file
        let newGifFileName: String = getRandomGifFile(gifFileName!)
            // load GIF image
        let isFileLoaded: Bool = loadGif(fromFile: newGifFileName, andUseManualFps: frameRateManual!, withFps: frameRate!)
        if isFileLoaded {
            currFrameCount = FIRST_FRAME
        }
        else {
            currFrameCount = FRAME_COUNT_NOT_USED
        }
        // calculate target and screen rectangle size
        screenRect = bounds
        targetRect = calcTargetRect(fromOption: viewOption!)
        // check if it is a file or a directory
        if isDir(gifFileName!) {
            // start a one-time timer at end of startAnimation otherwise the time for loading the GIF is part of the timer
            Timer.scheduledTimer(timeInterval: TimeInterval(changeIntervalInSec), target: self, selector: #selector(self.timerMethod), userInfo: nil, repeats: false)
        }
        if trigByTimer == false {
            if isPreview == false {
                // unhide window
                window!.orderBack(self)
            }
        }
    }

    override func stopAnimation() {
        if trigByTimer == false {
            // only call super method in case stopAnimation is not called by timerMethod
            super.stopAnimation()
            // only remove GL view in case stopAnimation is not called by timerMethod
            if isPreview == false {
                // remove glview from screensaver view
                removeFromSuperview()
            }
        }
        if (isPreview == false) && (loadAnimationToMem == true) {
            /*clean all pre-calculated bitmap images*/
            animationImages.removeAll()
        }
        img = nil
        currFrameCount = FRAME_COUNT_NOT_USED
    }

    override func animateOneFrame() {
        if currFrameCount == FRAME_COUNT_NOT_USED {
            // FRAME_COUNT_NOT_USED means no image is loaded and so we clear the screen with the set background color
            if isPreview == true {
                // only clear screen with background color (not OpenGL)
                NSColor(deviceRed: CGFloat(backgrRed), green: CGFloat(backgrGreen), blue: CGFloat(backgrBlue), alpha: CGFloat(NS_ALPHA_OPAQUE)).set()
                NSBezierPath.fill(screenRect)
            }
            else {
                // only clear screen with background color (OpenGL)
                glView?.openGLContext?.makeCurrentContext()
                glClearColor(backgrRed, backgrGreen, backgrBlue, GLclampf(GL_ALPHA_OPAQUE))
                glClear(GLbitfield(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT))
                glFlush()
                needsDisplay = true
            }
        }
        else {
            // draw the selected frame
            if isPreview == true {
                // In Preview Mode OpenGL leads to crashes (?) so we make a classical image draw
                //select current frame from GIF (Hint: gifRep is a sub-object from img)
                gifRep?.setProperty(.currentFrame, withValue: currFrameCount)
                // than clear screen with background color
                NSColor(deviceRed: CGFloat(backgrRed), green: CGFloat(backgrGreen), blue: CGFloat(backgrBlue), alpha: CGFloat(NS_ALPHA_OPAQUE)).set()
                NSBezierPath.fill(screenRect)
                // now draw frame
                img?.draw(in: targetRect)
            }
            else {
                // if we have no Preview Mode we use OpenGL to draw
                // change context to glview
                glView?.openGLContext?.makeCurrentContext()
                // first clear screen with background color
                glClearColor(backgrRed, backgrGreen, backgrBlue, GLclampf(GL_ALPHA_OPAQUE))
                glClear(GLbitfield(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT))
                // Start phase
                glPushMatrix()
                // defines the pixel resolution of the screen (can be smaller than real screen, but than you will see pixels)
                glOrtho(0, GLdouble(screenRect.size.width), GLdouble(screenRect.size.height), 0, -1, 1)
                glEnable(GLenum(GL_TEXTURE_2D))
                if gifRep?.hasAlpha == true {
                    glEnable(GLenum(GL_BLEND))
                    glBlendFunc(GLenum(GL_ONE), GLenum(GL_ONE_MINUS_SRC_ALPHA))
                }
                    //get one free texture name
                var frameTextureName: GLuint
                glGenTextures(1, &frameTextureName)
                //bind a Texture object to the name
                glBindTexture(GLenum(GL_TEXTURE_2D), frameTextureName)
                // load current bitmap as texture into the GPU
                glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GLfloat(GLenum(GL_LINEAR_MIPMAP_LINEAR)))
                glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GLfloat(GLenum(GL_LINEAR)))
                glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GLenum(GL_CLAMP_TO_EDGE)))
                glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GLenum(GL_CLAMP_TO_EDGE)))
                if loadAnimationToMem == true {
                        // we load bitmap data from memory and save CPU time (created during startAnimation)
                    let pixels: Data? = animationImages[currFrameCount] as? Data
                    glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, (Int32(gifRep!.pixelsWide)), (Int32(gifRep!.pixelsHigh)), 0, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), pixels)
                }
                else {
                    // bitmapData needs more CPU time to create bitmap data
                    gifRep.setProperty(.currentFrame, withValue: currFrameCount)
                    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (gifRep.pixelsWide as? GLint), (gifRep.pixelsHigh as? GLint), 0, GL_RGBA, GL_UNSIGNED_BYTE, gifRep.bitmapData)
                }
                    // generate Mipmap
                glGenerateMipmap(GL_TEXTURE_2D)
                    // define the target position of texture (related to screen defined by glOrtho) witch makes the texture visible
                let x: Float = targetRect.origin.x
                let y: Float = targetRect.origin.y
                let iheight: Float = targetRect.size.height
                let iwidth: Float = targetRect.size.width
                glBegin(GL_QUADS)
                glTexCoord2f(0.0, 0.0)
                glVertex2f(x, y)
                //Bottom left
                glTexCoord2f(1.0, 0.0)
                glVertex2f(x + iwidth, y)
                //Bottom right
                glTexCoord2f(1.0, 1.0)
                glVertex2f(x + iwidth, y + iheight)
                //Top right
                glTexCoord2f(0.0, 1.0)
                glVertex2f(x, y + iheight)
                //Top left
                glEnd()
                glDisable(GL_BLEND)
                glDisable(GL_TEXTURE_2D)
                //End phase
                glPopMatrix()
                //free texture object by name
                glDeleteTextures(1, frameTextureName)
                glFlush()
                glView.openGLContext?.flushBuffer()
                needsDisplay = true
            }
            //calculate next frame of GIF to show
            if currFrameCount < maxFrameCount - 1 {
                currFrameCount += 1
            }
            else {
                currFrameCount = FIRST_FRAME
            }
        }
        return
    }

    func hasConfigureSheet() -> Bool {
        // tell ScreenSaverEngine that screensaver has an Options dialog
        return true
    }

    func configureSheet() -> NSWindow {
        // Load XIB File that contains the Options dialog
        Bundle(for: AnimatedGifView).loadNibNamed("Options", owner: self, topLevelObjects: nil)
            // get filename from screensaver defaults
        let defaults = ScreenSaverDefaults(forModuleWithName: (Bundle(for: AnimatedGifView).bundleIdentifier) ?? "")
        let gifFileName = defaults?["GifFileName"] as? String
        let frameRate: Float? = defaults?.float(forKey: "GifFrameRate")
        let frameRateManual: Bool? = defaults?.bool(forKey: "GifFrameRateManual")
        let loadAniToMem: Bool? = defaults?.bool(forKey: "LoadAniToMem")
        let bgrRed: Float? = defaults?.float(forKey: "BackgrRed")
        let bgrGreen: Float? = defaults?.float(forKey: "BackgrGreen")
        let bgrBlue: Float? = defaults?.float(forKey: "BackgrBlue")
        var viewOpt: Int? = defaults?.integer(forKey: "ViewOpt")
        let changeInter: Int? = defaults?.integer(forKey: "ChangeInterval")
        // in the rarely case of an invalid value from default file we set an valid option
        if viewOpt > MAX_VIEW_OPT {
            viewOpt = VIEW_OPT_STRETCH_OPTIMAL
        }
        if isDir(gifFileName) {
            // if we have an directory an fps value for a file makes not much sense
            // we could calculate it for an randomly selected file but this would make thinks to complex
            labelFpsGif = Int("(dir)") ?? 0
            hideFps(fromFile: true)
            // enable time interval slider only in case that an directory is selected
            enableSliderChangeInterval(true)
        }
        else {
                // set file fps in GUI
            let duration: TimeInterval = getDurationFromGifFile(gifFileName)
            let fps = Float((1 / duration))
            labelFpsGif = Int(String(format: "%2.1f", fps)) ?? 0
            hideFps(fromFile: false)
            // disable time interval slider in case an file is selected
            enableSliderChangeInterval(false)
        }
            // set the visible value in dialog to the last saved value
        let version = Bundle(for: AnimatedGifView).object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        labelVersion = Int(version) ?? 0
        textFieldFileUrl = Int(gifFileName) ?? 0
        sliderFpsManual = frameRate
        checkButtonSetFpsManual.isState = frameRateManual
        checkButtonLoadIntoMem.isState = loadAniToMem
        if let aOpt = viewOpt {
            popupButtonViewOptions.selectItem(withTag: aOpt)
        }
        sliderChangeInterval = changeInter
        labelChangeInterval = Int("\(sliderChangeInterval)") ?? 0
        enableSliderFpsManual(frameRateManual)
        labelFpsManual = Int("\(sliderFpsManual)") ?? 0
        if let aRed = bgrRed, let aGreen = bgrGreen, let aBlue = bgrBlue {
            colorWellBackgrColor.color = NSColor(red: CGFloat(aRed), green: CGFloat(aGreen), blue: CGFloat(aBlue), alpha: NS_ALPHA_OPAQUE)
        }
            // set segment button depending if the launch-agent is active or not
        let userLaunchAgentsPath = "\("/Users/")\(NSUserName())\("/Library/LaunchAgents/com.waitsnake.animatedgif.plist")"
        let launchAgentFileExists: Bool = FileManager.default.fileExists(atPath: userLaunchAgentsPath)
        if launchAgentFileExists == true {
            segmentButtonLaunchAgent.selectedSegment = LOAD_BTN
        }
        else {
            segmentButtonLaunchAgent.selectedSegment = UNLOAD_BTN
        }
        // return the new created options dialog
        return optionsPanel
    }

    @IBAction func navigateSegmentButton(_ sender: Any) {
            // check witch segment of segment button was pressed and than start the according method
        let control = sender as? NSSegmentedControl
        let selectedSeg: Int? = control?.selectedSegment
        switch selectedSeg {
            case LOAD_BTN:
                loadAgent()
            case UNLOAD_BTN:
                unloadAgent()
            default:
                break
        }
    }

    @IBAction func closeConfigOk(_ sender: Any) {
            // read values from GUI elements
        var defaultsChanged = false
        let frameRate: Float = sliderFpsManual
        let gifFileName = "\(textFieldFileUrl)"
        let frameRateManual: Bool = checkButtonSetFpsManual.state
        let loadAniToMem: Bool = checkButtonLoadIntoMem.state
        let viewOpt: Int = popupButtonViewOptions.selectedTag()
        let colorPicked: NSColor? = colorWellBackgrColor.color
        let changeInt: Int = sliderChangeInterval
            // init access to screensaver defaults
        var defaults = ScreenSaverDefaults(forModuleWithName: (Bundle(for: AnimatedGifView).bundleIdentifier) ?? "")
        // check for changes in default values first
        if (gifFileName == defaults?["GifFileName"]) == false {
            defaultsChanged = true
        }
        if fabsf(defaults?.float(forKey: "GifFrameRate") - frameRate) > 0.01 {
            defaultsChanged = true
        }
        if defaults?.bool(forKey: "GifFrameRateManual") != frameRateManual {
            defaultsChanged = true
        }
        if defaults?.bool(forKey: "LoadAniToMem") != loadAniToMem {
            defaultsChanged = true
        }
        if defaults?.integer(forKey: "ViewOpt") != viewOpt {
            defaultsChanged = true
        }
        if defaults?.integer(forKey: "ChangeInterval") != changeInt {
            defaultsChanged = true
        }
        if fabs(defaults?.float(forKey: "BackgrRed") - colorPicked?.redComponent) > 0.01 {
            defaultsChanged = true
        }
        if fabs(defaults?.float(forKey: "BackgrGreen") - colorPicked?.greenComponent) > 0.01 {
            defaultsChanged = true
        }
        if fabs(defaults?.float(forKey: "BackgrBlue") - colorPicked?.blueComponent) > 0.01 {
            defaultsChanged = true
        }
        // write new default values
        defaults?["GifFileName"] = gifFileName
        defaults?.set(frameRate, forKey: "GifFrameRate")
        defaults?.set(frameRateManual, forKey: "GifFrameRateManual")
        defaults?.set(loadAniToMem, forKey: "LoadAniToMem")
        defaults?.set(viewOpt, forKey: "ViewOpt")
        if let aComponent = colorPicked?.redComponent {
            defaults?.set(Float(aComponent), forKey: "BackgrRed")
        }
        if let aComponent = colorPicked?.greenComponent {
            defaults?.set(Float(aComponent), forKey: "BackgrGreen")
        }
        if let aComponent = colorPicked?.blueComponent {
            defaults?.set(Float(aComponent), forKey: "BackgrBlue")
        }
        defaults?.set(changeInt, forKey: "ChangeInterval")
        defaults?.synchronize()
        // set new values to object attributes
        backgrRed = colorPicked?.redComponent
        backgrGreen = colorPicked?.greenComponent
        backgrBlue = colorPicked?.blueComponent
        // close color dialog and options dialog
        NSColorPanel.shared.close()
        NSApplication.shared.endSheet(optionsPanel)
        // check if any default value has changed and background mode is active
        if (defaultsChanged == true) && (segmentButtonLaunchAgent.selectedSegment == LOAD_BTN) {
            // in this case stop and restart ScreenSaverEngine
            unloadAgent()
            loadAgent()
        }
    }

    @IBAction func closeConfigCancel(_ sender: Any) {
        // close color dialog and options dialog
        NSColorPanel.shared.close()
        NSApplication.shared.endSheet(optionsPanel)
    }

    @IBAction func pressCheckboxSetFpsManual(_ sender: Any) {
            // enable or disable slider depending on checkbox
        let frameRateManual: Bool = checkButtonSetFpsManual.state == .on
        if frameRateManual {
            enableSliderFpsManual(true)
        }
        else {
            enableSliderFpsManual(false)
        }
    }

    @IBAction func selectSliderFpsManual(_ sender: Any) {
        // update label with actual selected value of slider
        labelFpsManual.stringValue = "\(Int("\(sliderFpsManual)") ?? 0)"
    }

    @IBAction func selectSliderChangeInterval(_ sender: Any) {
        // update label with actual selected value of slider
        labelChangeInterval.stringValue = "\(Int("\(sliderChangeInterval)") ?? 0)"
    }

    func enableSliderChangeInterval(_ enable: Bool) {
        if enable == true {
            sliderChangeInterval.isEnabled = true
            labelChangeInterval.textColor = NSColor.black
            labelChIntT1.textColor = NSColor.black
            labelChIntT2.textColor = NSColor.black
            labelChIntT3.textColor = NSColor.black
            labelChIntT4.textColor = NSColor.black
        }
        else {
            sliderChangeInterval.isEnabled = false
            labelChangeInterval.textColor = NSColor.lightGray
            labelChIntT1.textColor = NSColor.lightGray
            labelChIntT2.textColor = NSColor.lightGray
            labelChIntT3.textColor = NSColor.lightGray
            labelChIntT4.textColor = NSColor.lightGray
        }
    }

    func enableSliderFpsManual(_ enable: Bool) {
        if enable == true {
            sliderFpsManual.isEnabled = true
            labelFpsGif.textColor = NSColor.black
            labelFpsManual.textColor = NSColor.black
            labelFpsT1.textColor = NSColor.black
            labelFpsT2.textColor = NSColor.black
            labelFpsT3.textColor = NSColor.black
            labelFpsT4.textColor = NSColor.black
            labelFpsT5.textColor = NSColor.black
            labelFpsT6.textColor = NSColor.black
        }
        else {
            sliderFpsManual.isEnabled = false
            labelFpsGif.textColor = NSColor.lightGray
            labelFpsManual.textColor = NSColor.lightGray
            labelFpsT1.textColor = NSColor.lightGray
            labelFpsT2.textColor = NSColor.lightGray
            labelFpsT3.textColor = NSColor.lightGray
            labelFpsT4.textColor = NSColor.lightGray
            labelFpsT5.textColor = NSColor.lightGray
            labelFpsT6.textColor = NSColor.lightGray
        }
    }

    func hideFps(fromFile hide: Bool) {
        if hide == true {
            labelFpsGif.isHidden = true
            labelFpsT2.isHidden = true
            labelFpsT3.isHidden = true
        }
        else {
            labelFpsGif.isHidden = false
            labelFpsT2.isHidden = false
            labelFpsT3.isHidden = false
        }
    }

    @IBAction func sendFileButtonAction(_ sender: Any) {
        let openDlg = NSOpenPanel()
        // Enable the selection of files in the dialog.
        openDlg.canChooseFiles = true
        // Enable the selection of directories in the dialog.
        openDlg.canChooseDirectories = true
        // Disable the selection of more than one file
        openDlg.allowsMultipleSelection = false
        // set dialog to one level above of last selected file/directory
        if isDir("\(textFieldFileUrl)") {
            // in case of an directory remove one level of path before open it
            openDlg.directoryURL = URL(string: "\(textFieldFileUrl)")?.deletingLastPathComponent
        }
        else {
            // in case of an file remove two level of path before open it
            openDlg.directoryURL = URL(string: "\(textFieldFileUrl)")?.deletingLastPathComponent().deletingLastPathComponent
        }
        // try to 'focus' only on GIF files (Yes, I know all image types are working with NSImage)
        openDlg.allowedFileTypes = ["gif", "GIF"]
        // Display the dialog.  If the OK button was pressed,
        // process the files.
        if openDlg.runModal().rawValue == NSOKButton {
                // Get an array containing the full filenames of all
                // files and directories selected.
            let files = openDlg.urls
            let newSelectedFileOrDir: URL? = files[0]
            // set GUI element with selected URL
            textFieldFileUrl = Int(newSelectedFileOrDir?.absoluteString) ?? 0
            if isDir((newSelectedFileOrDir?.absoluteString)!) {
                // if we have an directory an fps value for a file makes not much sense
                // we could calculate it for an randomly selected file but this would make thinks to complex
                labelFpsGif.stringValue = "\(Int("(dir)") ?? 0)"
                hideFps(fromFile: true)
                // enable time interval slider only in case that an directory is selected
                enableSliderChangeInterval(true)
            }
            else {
                    // update file fps in GUI
                let duration: TimeInterval = getDurationFromGifFile((URL(string: newSelectedFileOrDir?.absoluteString ?? "")?.absoluteString)!)
                let fps = Float((1 / duration))
                labelFpsGif.stringValue = "\(Int(String(format: "%2.1f", fps)) ?? 0)"
                hideFps(fromFile: false)
                // disable time interval slider only in case that an file is selected
                enableSliderChangeInterval(false)
            }
        }
    }

    func loadAgent() {
            // create the plist agent file
        var plist = [AnyHashable: Any]()
            // check if Launch-Agent directory is there or not
        let userLaunchAgentsDir = "\("/Users/")\(NSUserName())\("/Library/LaunchAgents")"
        let launchAgentDirExists: Bool = FileManager.default.fileExists(atPath: userLaunchAgentsDir)
        if launchAgentDirExists == false {
            // if directory is not there create it
            try? FileManager.default.createDirectory(atPath: userLaunchAgentsDir, withIntermediateDirectories: true, attributes: nil)
        }
        var pathToScreenSaverEngine = "/System/Library/Frameworks/ScreenSaver.framework/Resources/ScreenSaverEngine.app/Contents/MacOS/ScreenSaverEngine"
        let osVer = ProcessInfo.processInfo.operatingSystemVersion as? OperatingSystemVersion
        if osVer!.majorVersion > 10 || osVer!.minorVersion > 12 {
            pathToScreenSaverEngine = "/System/Library/CoreServices/ScreenSaverEngine.app/Contents/MacOS/ScreenSaverEngine"
        }
            // set values here...
        let cfg = ["Label": "com.waitsnake.animatedgif", "ProgramArguments": [pathToScreenSaverEngine, "-window"], "KeepAlive": ["OtherJobEnabled": ["com.apple.SystemUIServer.agent": true, "com.apple.Finder": true, "com.apple.Dock.agent": true]], "ThrottleInterval": 0] as [String : Any]
        for (k, v) in cfg { plist.updateValue(v, forKey: k) }
            // saves the agent plist file
        let userLaunchAgentsPath = "\("/Users/")\(NSUserName())\("/Library/LaunchAgents/com.waitsnake.animatedgif.plist")"
        plist.write(toFile: userLaunchAgentsPath, atomically: true)
        plist.removeAll()
            // Workaround: disable clock before start, since this leads to a crash with option "-window" of ScreenSaverEngine
        let cmdstr2 = "\("defaults -currentHost write com.apple.screensaver showClock -bool NO")"
        self.system(cmdstr2)
            // start the launch agent
        let cmdstr = "launchctl load \(userLaunchAgentsPath) &"
        self.system(cmdstr)
    }

    func unloadAgent() {
            // stop the launch agent
        let userLaunchAgentsPath = "\("/Users/")\(NSUserName())\("/Library/LaunchAgents/com.waitsnake.animatedgif.plist")"
        let cmdstr = "\("launchctl unload ")\(userLaunchAgentsPath)"
        self.system(cmdstr)
        // remove the plist agent file
        try? FileManager.default.removeItem(atPath: userLaunchAgentsPath)
    }

    func pictureRatio(fromWidth iWidth: Float, andHeight iHeight: Float) -> Float {
        return iWidth / iHeight
    }

    func calcWidth(fromRatio iRatio: Float, andHeight iHeight: Float) -> Float {
        return iRatio * iHeight
    }

    func calcHeight(fromRatio iRatio: Float, andWidth iWidth: Float) -> Float {
        return iWidth / iRatio
    }

    func isDir(_ fileOrDir: String) -> Bool {
        var pathExist = false
        var isDir:ObjCBool = false
            // create an NSURL object from the NSString containing an URL
        let fileOrDirUrl = URL(string: fileOrDir)
            // fileExistsAtPath:isDirectory only works with classical Path
        let fileOrDirPath: String? = fileOrDirUrl?.path
        // check if user selected an directory or path
        if let aPath = fileOrDirPath {
            pathExist = FileManager.default.fileExists(atPath: aPath, isDirectory: &isDir)
        }
        if pathExist == true {
            // path was found
            if isDir.boolValue {
                return true
            }
            else {
                return false
            }
        }
        else {
            return false
        }
    }

    func getRandomGifFile(_ fileOrDir: String) -> String {
            // check if it is a file or directory
        let isDir: Bool = self.isDir(fileOrDir)
        if isDir == true {
                // we have an directory
                // an array of all files types and also all sub-directories
            let files = try? FileManager.default.contentsOfDirectory(at: URL(string: fileOrDir)!, includingPropertiesForKeys: [], options: .skipsHiddenFiles)
                // create an filter for GIF files
            let predicate = NSPredicate(format: "pathExtension == 'gif'")
                // apply filer for GIF files only to an new array
            let filesFilter = (files as NSArray?)?.filtered(using: predicate)
            if filesFilter != nil {
                    // directory includes one or more GIF files
                    // how many GIF files we have found
                let numberOfFiles: Int? = filesFilter?.count
                    // generate an random number with upper boundary of the number of found GIF files
                let randFile = Int(arc4random_uniform((numberOfFiles as? UInt32)!))
                // return a NSString of with an URL of the randomly selected GIF in the list
                return (filesFilter?[randFile ?? 0]?.absoluteString) ?? ""
            }
            else {
                // directory includes not a single GIF
                // return an empty NSString
                return ""
            }
        }
        else {
            // a file was found
            // return string as it is
            return fileOrDir
        }
    }

    func calcTargetRect(fromOption option: Int) -> NSRect {
            // set some values screensaver and GIF image size
        let mainScreenRect: NSRect? = NSScreen.main?.frame
        let screenRe: NSRect = bounds
        var targetRe: NSRect = screenRe
        let screenRatio: Float = pictureRatio(fromWidth: Float(screenRe.size.width), andHeight: Float(screenRe.size.height))
        let imgRatio: Float = pictureRatio(fromWidth: Float(img!.size.width), andHeight: Float(img!.size.height))
        var scaledHeight: CGFloat
        var scaledWidth: CGFloat
        if option == VIEW_OPT_STRETCH_OPTIMAL {
            // fit image optimal to screen
            if imgRatio >= screenRatio {
                targetRe.size.height = CGFloat(calcHeight(fromRatio: imgRatio, andWidth: Float(screenRe.size.width)))
                targetRe.origin.y = (screenRe.size.height - targetRe.size.height) / 2
                targetRe.size.width = screenRe.size.width
                targetRe.origin.x = screenRe.origin.x
            }
            else {
                targetRe.size.width = CGFloat(calcWidth(fromRatio: imgRatio, andHeight: Float(screenRe.size.height)))
                targetRe.origin.x = (screenRe.size.width - targetRe.size.width) / 2
                targetRe.size.height = screenRe.size.height
                targetRe.origin.y = screenRe.origin.y
            }
        }
        else if option == VIEW_OPT_STRETCH_MAXIMAL {
            // stretch image maximal to screen
            targetRe = screenRe
        }
        else if option == VIEW_OPT_KEEP_ORIG_SIZE {
            if isPreview == false {
                // in case of NO preview mode: simply keep original size of image
                targetRe.size.height = (img?.size.height)!
                targetRe.size.width = (img?.size.width)!
                targetRe.origin.y = (screenRe.size.height - (img?.size.height)!) / 2
                targetRe.origin.x = (screenRe.size.width - (img?.size.width)!) / 2
            }
            else {
                // in case of preview mode: we also need to calculate the ratio between the size of the physical main screen and the size of the preview window to scale the image down.
                scaledHeight = screenRe.size.height / (mainScreenRect?.size.height)! * (img?.size.height)!
                scaledWidth = screenRe.size.width / (mainScreenRect?.size.width)! * (img?.size.width)!
                targetRe.size.height = scaledHeight
                targetRe.size.width = scaledWidth
                targetRe.origin.y = (screenRe.size.height - scaledHeight) / 2
                targetRe.origin.x = (screenRe.size.width - scaledWidth) / 2
            }
        }
        else if option == VIEW_OPT_STRETCH_SMALL_SIDE {
            // stretch image to smallest side
            if imgRatio >= screenRatio {
                targetRe.size.height = screenRe.size.height
                targetRe.origin.y = screenRe.origin.y
                targetRe.size.width = CGFloat(calcWidth(fromRatio: imgRatio, andHeight: Float(screenRe.size.height)))
                targetRe.origin.x = -1 * (targetRe.size.width - screenRe.size.width) / 2
            }
            else {
                targetRe.size.width = screenRe.size.width
                targetRe.origin.x = screenRe.origin.x
                targetRe.size.height = CGFloat(calcHeight(fromRatio: imgRatio, andWidth: Float(screenRe.size.width)))
                targetRe.origin.y = -1 * (targetRe.size.height - screenRe.size.height) / 2
            }
        }
        else {
            /*default is VIEW_OPT_STRETCH_MAXIMAL*/
            // stretch image maximal to screen
            targetRe = screenRe
        }
        return targetRe
    }

    func loadGif(fromFile gifFileName: String, andUseManualFps manualFpsActive: Bool, withFps fps: Float) -> Bool {
        // load the GIF
        if let aName = URL(string: gifFileName) {
            img = NSImage(contentsOf: aName)
        }
        // check if a GIF was loaded
        if (img != nil) {
            // get an NSBitmapImageRep that we need to get to the bitmap data and properties of GIF
            gifRep = img?.representations()[FIRST_FRAME] as? NSBitmapImageRep
            // get max number of frames of GIF
            maxFrameCount = Int(gifRep!.value(forProperty: .frameCount))
            // setup FPS of loaded GIF
            if manualFpsActive {
                // set frame rate manual
                animationTimeInterval = TimeInterval((1 / fps))
            }
            else {
                    // set frame duration from data from gif file
                let duration: TimeInterval = getDurationFromGifFile(gifFileName)
                animationTimeInterval = duration
            }
            // in case of no review mode and active config option create an array in memory with all frames of bitmap in bitmap format (can be used directly as OpenGL texture)
            if (isPreview == false) && (loadAnimationToMem == true) {
                animationImages = [AnyHashable]()
                for frame in 0..<maxFrameCount {
                    gifRep?.setProperty(.currentFrame, withValue: frame)
                        // bitmapData needs most CPU time during animation.
                        // thats why we execute bitmapData here during startAnimation and not in animateOneFrame. the start of screensaver will be than slower of cause, but during animation itself we need less CPU time
                    let data = UInt8(gifRep?.bitmapData ?? 0)
                    let size = UInt(gifRep!.bytesPerPlane)
                    UInt8(                    // copy the bitmap data into an NSData object, that can be save transferred to animateOneFrame
NSData) * imgData = Data(bytes: data, length: Int(size))
                    animationImages.append(imgData)
                }
            }
            // GIF was loaded
            return true
        }
        else {
            // there was no GIF loaded
            return false
        }
    }

    func getDurationFromGifFile(_ gifFileName: String) -> TimeInterval {
            /* If the fps is "too fast" NSBitmapImageRep gives back a clamped value for slower fps and not the value from the file! WTF? */
            /*
                [gifRep setProperty:NSImageCurrentFrame withValue:@(2)];
                NSTimeInterval currFrameDuration = [[gifRep valueForProperty: NSImageCurrentFrameDuration] floatValue];
                return currFrameDuration;
                */
            // As workaround for the problem of NSBitmapImageRep class we use CGImageSourceCopyPropertiesAtIndex that always gives back the real value
        let source: CGImageSource = CGImageSourceCreateWithURL((URL(string: gifFileName) as? CFURLRef), nil)
        if source != nil {
            let cfdProperties: CFDictionary = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            let properties = CFBridgingRelease(cfdProperties)
            let duration = (properties[(kCGImagePropertyGIFDictionary as? String)]?[(kCGImagePropertyGIFUnclampedDelayTime as? String)]) as? NSNumber
                //scale duration by 1000 to get ms, because it is in sec and a fraction between 1 and 0
            let durMs = Int((Double(duration ?? 0.0) * 1000.0))
            // We want to catch the case that duration is 0ms (infinity fps!), because vale was not set in frame 0 frame of GIF
            if durMs == 0 {
                // wenn NO duration was set, we use an default duration (15 fps)
                return DEFAULT_ANIME_TIME_INTER
            }
            else {
                // if we have a valid duration than return it
                return TimeInterval(Double(duration ?? 0.0))
            }
        }
        else {
            // if not even a GIF file could be open, we use an default duration (15 fps)
            return DEFAULT_ANIME_TIME_INTER
        }
    }
}
