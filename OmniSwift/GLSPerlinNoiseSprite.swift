//
//  GLSPerlinNoiseSprite.swift
//  OmniSwift
//
//  Created by Cooper Knaak on 5/27/15.
//  Copyright (c) 2015 Cooper Knaak. All rights reserved.
//

import GLKit

public protocol DoubleBuffered {
    var buffer:GLSFrameBuffer { get }
    var shouldRedraw:Bool { get set }
    var bufferIsDirty:Bool { get }
    func renderToTexture()
    
}

public class GLSPerlinNoiseSprite: GLSSprite, DoubleBuffered {
    
    // MARK: - Types
    
    public class PerlinNoiseProgram {
        
        var program:GLuint { return self.attributeBridger.program }
        let attributeBridger:GLAttributeBridger
        
        let u_Projection:GLint
        let u_TextureInfo:GLint
        let u_NoiseTextureInfo:GLint
        let u_GradientInfo:GLint
        let u_PermutationInfo:GLint
        let u_Offset:GLint
        let u_NoiseDivisor:GLint
        let u_Alpha:GLint
        let u_Period:GLint
        let a_Position:GLint
        let a_Texture:GLint
        let a_NoiseTexture:GLint
        
        let u_NoiseAngle:GLint
        
        init(type:NoiseType) {
            
            
            let program:GLuint
            switch type {
            case .Default:
                program = ShaderHelper.programForString("Perlin Noise Shader")!
            case .Fractal:
                program = ShaderHelper.programForString("Perlin Fractal Noise Shader")!
            case .Abs:
                program = ShaderHelper.programForString("Perlin Abs Noise Shader")!
            case .Sin:
                program = ShaderHelper.programForString("Perlin Sin Noise Shader")!
            }
            
            while glGetError() != GLenum(GL_NO_ERROR) {
                
            }
            self.u_Projection       = glGetUniformLocation(program, "u_Projection")
            self.u_TextureInfo      = glGetUniformLocation(program, "u_TextureInfo")
            self.u_NoiseTextureInfo = glGetUniformLocation(program, "u_NoiseTextureInfo")
            self.u_GradientInfo     = glGetUniformLocation(program, "u_GradientInfo")
            self.u_PermutationInfo  = glGetUniformLocation(program, "u_PermutationInfo")
            self.u_Offset           = glGetUniformLocation(program, "u_Offset")
            self.u_NoiseDivisor     = glGetUniformLocation(program, "u_NoiseDivisor")
            self.u_Alpha            = glGetUniformLocation(program, "u_Alpha")
            self.u_Period           = glGetUniformLocation(program, "u_Period")
            self.a_Position     = glGetAttribLocation(program, "a_Position")
            self.a_Texture      = glGetAttribLocation(program, "a_Texture")
            self.a_NoiseTexture = glGetAttribLocation(program, "a_NoiseTexture")

            self.attributeBridger = GLAttributeBridger(program: program)
            
            let atts = [self.a_Position, self.a_Texture, self.a_NoiseTexture]
            self.attributeBridger.addAttributes(atts)
            
            if (type == .Sin) {
                self.u_NoiseAngle = glGetUniformLocation(program, "u_NoiseAngle")
            } else {
                self.u_NoiseAngle = 0
            }
            
        }//initialize
        
    }
    
    public struct PerlinNoiseVertex {
        var position:(GLfloat, GLfloat) = (0.0, 0.0)
        var texture:(GLfloat, GLfloat)  = (0.0, 0.0)
        public var noiseTexture:(GLfloat, GLfloat, GLfloat) = (0.0, 0.0, 0.0)
        var aspectRatio:(GLfloat, GLfloat) = (0.0, 0.0)
    }
    
    public enum NoiseType: String {
        case Default    = "Default"
        case Fractal    = "Fractal"
        case Abs        = "Abs"
        case Sin        = "Sin"
    }
    
    // MARK: - Properties
    
    public private(set) var noiseProgram = PerlinNoiseProgram(type: .Default)
    
    ///Texture used to find, generate, and interpolate between noise values.
    public var noiseTexture:Noise3DTexture2D
    ///Gradient of colors that noise is mapped to.
    public var gradient:GLGradientTexture2D
    ///Texture multiplied into the final output color.
    public var shadeTexture:CCTexture? {
        didSet {
            self.shadeTextureChanged()
        }
    }
    
    public let noiseVertices:TexturedQuadVertices<PerlinNoiseVertex> = []
//    public let buffer:GLSFrameBuffer
    public private(set) var buffer:GLSFrameBuffer
    
    ///What type of noise is drawn (Default, Fractal, etc.)
    public var noiseType:NoiseType = NoiseType.Default {
        didSet {
            self.noiseProgram = PerlinNoiseProgram(type: noiseType)
            self.bufferIsDirty = true
        }
    }
    
    ///Conceptually, the size of the noise. How much noise you can see.
    public var noiseSize:CGSize = CGSize(square: 1.0) {
        didSet {
            self.noiseSizeChanged()
            if self.shouldRedraw && !(noiseSize.width ~= oldValue.width || noiseSize.height ~= oldValue.height) {
                self.renderToTexture()
            } else {
                self.bufferIsDirty = true
            }
        }
    }
    ///Accessor for *noiseSize.width*
    public var noiseWidth:CGFloat {
        get {
            return self.noiseSize.width
        }
        set {
            self.noiseSize.width = newValue
        }
    }
    ///Accessor for *noiseSize.height*
    public var noiseHeight:CGFloat {
        get {
            return self.noiseSize.height
        }
        set {
            self.noiseSize.height = newValue
        }
    }
    
    ///Offset of noise texture. Note that the texture is not redrawn when *offset* is changed.
    public var offset:SCVector3 = SCVector3() {
        didSet {
            self.offset = SCVector3(x: self.offset.x % 255.0, y: self.offset.y % 255.0, z: self.offset.z % 255.0)
            if self.shouldRedraw && !(self.offset ~= oldValue) {
                self.renderToTexture()
            } else {
                self.bufferIsDirty = true
            }
        }
    }
    ///Speed at with offset changes. Note that the texture is not redrawn when *offset* is changed.
    public var offsetVelocity = SCVector3()
    ///How much the noise is blended with the rest of the texture. 0.0 for no noise and 1.0 for full noise.
    public var noiseAlpha:CGFloat = 1.0
    
    ///The period is how long it takes for the noise to begin repeating. Defaults to 256 (which doesn't actually have an effect).
    public var period:(x:Int, y:Int, z:Int) = (256, 256, 256) {
        didSet {
            self.bufferIsDirty = true
        }
    }
    public var xyPeriod:(x:Int, y:Int) {
        get {
            return (self.period.x, self.period.y)
        }
        set {
            self.period = (newValue.x, newValue.y, self.period.z)
        }
    }
    public var yzPeriod:(y:Int, z:Int) {
        get {
            return (self.period.y, self.period.z)
        }
        set {
            self.period = (self.period.x, newValue.y, newValue.z)
        }
    }
    public var xzPeriod:(x:Int, z:Int) {
        get {
            return (self.period.x, self.period.z)
        }
        set {
            self.period = (newValue.x, self.period.y, newValue.z)
        }
    }
    
    /**
    What to divide the 3D Noise Value by.
    
    Since perlin noise actually returns values
    in the range [-0.7, 0.7] (according to http://paulbourke.net/texture_colour/perlin/ ),
    I don't get the full range of the gradient. Thus,
    by adding a divisor, I can scale the noise to
    the full range. Default value is 0.7, because
    that should cause noise to range from [-1.0, 1.0].
    */
    public var noiseDivisor:CGFloat = 0.7 {
        didSet {
            if self.noiseDivisor <= 0.0 {
                self.noiseDivisor = 1.0
            }
            self.bufferIsDirty = true
        }
    }
    
    public var noiseAngle:CGFloat = 0.0 {
        didSet {
            self.noiseAngle = self.noiseAngle % CGFloat(2.0 * M_PI)
            self.bufferIsDirty = true;
        }
    }
    
    public var shouldRedraw = false
    public private(set) var bufferIsDirty = false
    
    public private(set) var fadeAnimation:NoiseFadeAnimation? = nil
    
    // MARK: - Setup
    
    public init(size:CGSize, texture:CCTexture?, noise:Noise3DTexture2D, gradient:GLGradientTexture2D) {
        
        self.buffer = GLSFrameBuffer(size: size)
        self.shadeTexture = texture
        self.noiseTexture = noise
        self.gradient = gradient
        
//        var p:[GLint] = []
        /*for cur in self.noiseTexture.noise.permutations {
        p.append(GLint(cur))
        }*/
        /*let perms = self.noiseTexture.noise.permutations
        for iii in 0..<1028 {
        let cur = perms[iii % perms.count]
        p.append(GLint(cur))
        }
        self.permutations = p*/
        
        for _ in 0..<TexturedQuad.verticesPerQuad {
            self.noiseVertices.append(PerlinNoiseVertex())
        }
        
        //        super.init(position: CGPoint.zero, size: size)
        super.init(position: size.center, size: size, texture: self.buffer.ccTexture)
        
        let sizeAsPoint = size.getCGPoint()
        self.noiseVertices.iterateWithHandler() { index, vertex in
            let curPoint = TexturedQuad.pointForIndex(index)
            vertex.texture = curPoint.getGLTuple()
            vertex.position = (curPoint * sizeAsPoint).getGLTuple()
            
            vertex.noiseTexture = (vertex.texture.0, vertex.texture.1, 0.0)
            
            vertex.aspectRatio = (curPoint * CGPoint(x: 1.0, y: size.height / size.width)).getGLTuple()
            return
        }
        
//        self.noiseTextureChanged()
        self.shadeTextureChanged()
    }
    
    // MARK: - Logic
    
    public override func update(dt: CGFloat) {
        super.update(dt)
        
        self.offset += self.offsetVelocity * dt
        
        if let fadeAnimation = self.fadeAnimation {
            fadeAnimation.update(dt)
            if fadeAnimation.isFinished {
                fadeAnimation.completionHandler?()
                self.fadeAnimation = nil
            }
        }
    }//update
    
    ///Render noise to background texture (*buffer*).
    public func renderToTexture() {
        guard let success = self.framebufferStack?.pushGLSFramebuffer(self.buffer) where success else {
            print("Error: Couldn't push framebuffer!")
            print("Stack: \(self.framebufferStack)")
            return
        }
        
        glClearColor(0.0, 0.0, 0.0, 0.0)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        
        glUseProgram(self.noiseProgram.program)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), self.noiseProgram.attributeBridger.vertexBuffer)
        glBufferData(GLenum(GL_ARRAY_BUFFER), self.noiseVertices.size, self.noiseVertices.vertices, GLenum(GL_STATIC_DRAW))
        
//        let proj = GLSUniversalRenderer.sharedInstance.projection
        let proj = self.projection
        glUniformMatrix4fv(self.noiseProgram.u_Projection, 1, 0, proj.values)
        
        glUniform1i(self.noiseProgram.u_TextureInfo, 0)
        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), self.shadeTexture?.name ?? 0)
        
        glUniform1i(self.noiseProgram.u_NoiseTextureInfo, 1)
        glActiveTexture(GLenum(GL_TEXTURE1))
        glBindTexture(GLenum(GL_TEXTURE_2D), self.noiseTexture.noiseTexture)
        
        glUniform1i(self.noiseProgram.u_GradientInfo, 2)
        glActiveTexture(GLenum(GL_TEXTURE2))
        glBindTexture(GLenum(GL_TEXTURE_2D), self.gradient.textureName)
        
        glUniform1i(self.noiseProgram.u_PermutationInfo, 3)
        glActiveTexture(GLenum(GL_TEXTURE3))
        glBindTexture(GLenum(GL_TEXTURE_2D), self.noiseTexture.permutationTexture)
        
//        glUniform1iv(self.noiseProgram.u_Permutations, 256, self.permutations)
        self.bridgeUniform3f(self.noiseProgram.u_Offset, vector: self.offset)
        glUniform1f(self.noiseProgram.u_NoiseDivisor, GLfloat(self.noiseDivisor))
        glUniform1f(self.noiseProgram.u_Alpha, GLfloat(self.noiseAlpha))
        glUniform3i(self.noiseProgram.u_Period, GLint(self.period.x), GLint(self.period.y), GLint(self.period.z))
        
        if (self.noiseType == .Sin) {
            glUniform1f(self.noiseProgram.u_NoiseAngle, GLfloat(self.noiseAngle))
        }
        
        self.noiseProgram.attributeBridger.enableAttributes()
        self.noiseProgram.attributeBridger.bridgeAttributesWithSizes([2, 2, 3], stride: self.noiseVertices.stride)
        
        glDrawArrays(TexturedQuad.drawingMode, 0, GLsizei(self.noiseVertices.count))
        
        self.noiseProgram.attributeBridger.disableAttributes()
        self.framebufferStack?.popFramebuffer()
        glActiveTexture(GLenum(GL_TEXTURE0))
        
        self.bufferIsDirty = false
    }
    
    public func shadeTextureChanged() {
        if let nt = self.shadeTexture {
            let bl = nt.frame.bottomLeftGL
            let br = nt.frame.bottomRightGL
            let tl = nt.frame.topLeftGL
            let tr = nt.frame.topRightGL
            
            self.noiseVertices.alterVertex(TexturedQuad.VertexName.TopLeft) {
                $0.texture = tl.getGLTuple()
                return
            }
            self.noiseVertices.alterVertex(TexturedQuad.VertexName.BottomLeft) {
                $0.texture = bl.getGLTuple()
                return
            }
            self.noiseVertices.alterVertex(TexturedQuad.VertexName.TopRight) {
                $0.texture = tr.getGLTuple()
                return
            }
            self.noiseVertices.alterVertex(TexturedQuad.VertexName.BottomRight) {
                $0.texture = br.getGLTuple()
                return
            }
        }
    }
    
    public func noiseSizeChanged() {
        
        self.noiseVertices.iterateWithHandler() { index, vertex in
            let curPoint = TexturedQuad.pointForIndex(index)
            let curTex = (curPoint * self.noiseSize).getGLTuple()
            vertex.noiseTexture = (curTex.0, curTex.1, vertex.noiseTexture.2)
            return
        }
        
    }//noise size changed
    
    public override func contentSizeChanged() {
        self.buffer = GLSFrameBuffer(size: self.contentSize)
        self.texture = self.buffer.ccTexture
        
        let sizeAsPoint = self.contentSize.getCGPoint()
        self.noiseVertices.iterateWithHandler() { index, vertex in
            let curPoint = TexturedQuad.pointForIndex(index)
            vertex.position = (curPoint * sizeAsPoint).getGLTuple()
        }
        
        super.contentSizeChanged()
    }
    
    public func performFadeWithDuration(duration:CGFloat, appearing:Bool, completion:dispatch_block_t?) {
        let fadeAnimation = NoiseFadeAnimation(sprite: self, duration: duration, appearing: appearing)
        if let completion = completion {
            fadeAnimation.completionHandler = completion
        }
        self.fadeAnimation = fadeAnimation
    }
    
}