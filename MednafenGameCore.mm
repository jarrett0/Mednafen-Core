/*
 Copyright (c) 2013, OpenEmu Team


 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
     * Neither the name of the OpenEmu Team nor the
       names of its contributors may be used to endorse or promote products
       derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "MednafenGameCore.h"
#import <OpenEmuBase/OERingBuffer.h>
#import "OELynxSystemResponderClient.h"
#import "OEPCESystemResponderClient.h"
#import "OEPCFXSystemResponderClient.h"
#import "OEPSXSystemResponderClient.h"
#import "OEVBSystemResponderClient.h"
#import "OEWSSystemResponderClient.h"

#include "mednafen/mednafen-types.h"
#include "mednafen/mednafen.h"
#include "mednafen/git.h"
#include "mednafen/general.h"

static MDFNGI *game;
static MDFN_Surface *surf;

enum systemTypes{ lynx, pce, pcfx, psx, vb, wswan };

@interface MednafenGameCore () <OELynxSystemResponderClient, OEPCESystemResponderClient, OEPCFXSystemResponderClient, OEPSXSystemResponderClient, OEVBSystemResponderClient, OEWSSystemResponderClient>
{
    int systemType;
    int videoWidth, videoHeight;
    int videoOffsetX, videoOffsetY;
    int16_t pad[2][16];
    NSString *romName;
    double sampleRate;
    double masterClock;
    
    NSString *mednafenCoreModule;
    NSTimeInterval mednafenCoreTiming;
    OEIntSize mednafenCoreAspect;
}

@end

MednafenGameCore *current;
@implementation MednafenGameCore

static void mednafen_init()
{
    std::vector<MDFNGI*> ext;
    MDFNI_InitializeModules(ext);
    
    std::vector<MDFNSetting> settings;
    
    NSString *batterySavesDirectory = current.batterySavesDirectoryPath;
    NSString *biosPath = [NSString pathWithComponents:@[
                          [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) lastObject],
                          @"OpenEmu", @"BIOS"]];
    
    MDFNSetting pce_setting = { "pce.cdbios", MDFNSF_EMU_STATE, "PCE CD BIOS", NULL, MDFNST_STRING, [[[biosPath stringByAppendingPathComponent:@"syscard3"] stringByAppendingPathExtension:@"pce"] UTF8String] };
    
    MDFNSetting pcfx_setting = { "pcfx.bios", MDFNSF_EMU_STATE, "PCFX BIOS", NULL, MDFNST_STRING, [[[biosPath stringByAppendingPathComponent:@"pcfx"] stringByAppendingPathExtension:@"rom"] UTF8String] };
    
    MDFNSetting jp_setting = { "psx.bios_jp", MDFNSF_EMU_STATE, "SCPH-5500 BIOS", NULL, MDFNST_STRING, [[[biosPath stringByAppendingPathComponent:@"scph5500"] stringByAppendingPathExtension:@"bin"] UTF8String] };
    MDFNSetting na_setting = { "psx.bios_na", MDFNSF_EMU_STATE, "SCPH-5501 BIOS", NULL, MDFNST_STRING, [[[biosPath stringByAppendingPathComponent:@"scph5501"] stringByAppendingPathExtension:@"bin"] UTF8String] };
    MDFNSetting eu_setting = { "psx.bios_eu", MDFNSF_EMU_STATE, "SCPH-5502 BIOS", NULL, MDFNST_STRING, [[[biosPath stringByAppendingPathComponent:@"scph5502"] stringByAppendingPathExtension:@"bin"] UTF8String] };
    MDFNSetting filesys = { "filesys.path_sav", MDFNSF_NOFLAGS, "Memcards", NULL, MDFNST_STRING, [batterySavesDirectory UTF8String] };
    
    // dox http://mednafen.sourceforge.net/documentation/09x/vb.html
    MDFNSetting vb_parallax = { "vb.disable_parallax", MDFNSF_EMU_STATE, "Disable parallax for BG and OBJ rendering", NULL, MDFNST_BOOL, "1", NULL, NULL, NULL };
    MDFNSetting vb_anaglyph_preset = { "vb.anaglyph.preset", MDFNSF_EMU_STATE, "Disable anaglyph preset", NULL, MDFNST_BOOL, "disabled", NULL, NULL, NULL };
    MDFNSetting vb_anaglyph_lcolor = { "vb.anaglyph.lcolor", MDFNSF_EMU_STATE, "Anaglyph l color", NULL, MDFNST_BOOL, "0xFF0000", NULL, NULL, NULL };
    //MDFNSetting vb_anaglyph_lcolor = { "vb.anaglyph.lcolor", MDFNSF_EMU_STATE, "Anaglyph l color", NULL, MDFNST_BOOL, "0xFFFFFF", NULL, NULL, NULL };
    MDFNSetting vb_anaglyph_rcolor = { "vb.anaglyph.rcolor", MDFNSF_EMU_STATE, "Anaglyph r color", NULL, MDFNST_BOOL, "0x000000", NULL, NULL, NULL };
    //MDFNSetting vb_allow_draw_skip = { "vb.allow_draw_skip", MDFNSF_EMU_STATE, "Allow draw skipping", NULL, MDFNST_BOOL, "1", NULL, NULL, NULL };
    //MDFNSetting vb_instant_display_hack = { "vb.instant_display_hack", MDFNSF_EMU_STATE, "ADisplay latency reduction hack", NULL, MDFNST_BOOL, "1", NULL, NULL, NULL };
    
    settings.push_back(pce_setting);
    
    settings.push_back(pcfx_setting);
    
    settings.push_back(jp_setting);
    settings.push_back(na_setting);
    settings.push_back(eu_setting);
    settings.push_back(filesys);
    
    settings.push_back(vb_parallax);
    settings.push_back(vb_anaglyph_preset);
    settings.push_back(vb_anaglyph_lcolor);
    settings.push_back(vb_anaglyph_rcolor);
    //settings.push_back(vb_allow_draw_skip);
    //settings.push_back(vb_instant_display_hack);
    
    MDFNI_Initialize([biosPath UTF8String], settings);
}

- (id)init
{
    if((self = [super init]))
    {
        memset(pad, 0, sizeof(int16_t) * 10);
        current = self;
    }
    
    return self;
}

- (void)dealloc
{
    delete surf;
}

# pragma mark - Execution

static void emulation_run()
{
    update_input();

    static int16_t sound_buf[0x10000];
    MDFN_Rect rects[game->fb_height];
    rects[0].w = ~0;

    EmulateSpecStruct spec = {0};
    spec.surface = surf;
    spec.SoundRate = current->sampleRate;
    spec.SoundBuf = sound_buf;
    spec.LineWidths = rects;
    spec.SoundBufMaxSize = sizeof(sound_buf) / 2;
    spec.SoundVolume = 1.0;
    spec.soundmultiplier = 1.0;

    MDFNI_Emulate(&spec);

    current->mednafenCoreTiming = current->masterClock / spec.MasterCycles;

    if(current->systemType == psx)
    {
        current->videoWidth = rects[0].w;

        // Crop overscan for NTSC. Might remove as this kinda sucks
        if (!game->isPalPSX)
            switch (current->videoWidth)
        {
                // The shifts are not simply (padded_width - real_width) / 2.
            case 350:
                current->videoOffsetX = 14;
                current->videoWidth = 320;
                break;

            case 700:
                current->videoOffsetX = 33;
                current->videoWidth = 640;
                break;

            case 400:
                current->videoOffsetX = 15;
                current->videoWidth = 364;
                break;

            case 280:
                current->videoOffsetX = 10;
                current->videoWidth = 256;
                break;

            case 560:
                current->videoOffsetX = 26;
                current->videoWidth = 512;
                break;

            default:
                // This shouldn't happen.
                break;
        }
    }
    else if(game->multires)
    {
        current->videoWidth = rects[0].w;
        current->videoOffsetX = rects[0].x;
    }
    else
    {
        current->videoWidth = spec.DisplayRect.w;
        current->videoOffsetX = spec.DisplayRect.x;
    }

    current->videoHeight = spec.DisplayRect.h;
    current->videoOffsetY = spec.DisplayRect.y;

    update_audio_batch(spec.SoundBuf, spec.SoundBufSize);
}

- (BOOL)loadFileAtPath:(NSString *)path
{
    if([[self systemIdentifier] isEqualToString:@"openemu.system.lynx"])
    {
        systemType = lynx;

        mednafenCoreModule = @"lynx";
        mednafenCoreAspect = OEIntSizeMake(8, 5);
        sampleRate         = 48000;
    }

    if([[self systemIdentifier] isEqualToString:@"openemu.system.pce"])
    {
        systemType = pce;

        mednafenCoreModule = @"pce";
        mednafenCoreAspect = OEIntSizeMake(4, 3);
        sampleRate         = 48000;
    }

    if([[self systemIdentifier] isEqualToString:@"openemu.system.pcfx"])
    {
        systemType = pcfx;

        mednafenCoreModule = @"pcfx";
        mednafenCoreAspect = OEIntSizeMake(4, 3);
        sampleRate         = 48000;
    }

    if([[self systemIdentifier] isEqualToString:@"openemu.system.psx"])
    {
        systemType = psx;

        mednafenCoreModule = @"psx";
        mednafenCoreAspect = OEIntSizeMake(4, 3);
        sampleRate         = 44100;
    }

    if([[self systemIdentifier] isEqualToString:@"openemu.system.vb"])
    {
        systemType = vb;

        mednafenCoreModule = @"vb";
        mednafenCoreAspect = OEIntSizeMake(12, 7);
        sampleRate         = 48000;
    }

    if([[self systemIdentifier] isEqualToString:@"openemu.system.ws"])
    {
        systemType = wswan;

        mednafenCoreModule = @"wswan";
        mednafenCoreAspect = OEIntSizeMake(14, 9);
        sampleRate         = 48000;
    }

    mednafen_init();

    game = MDFNI_LoadGame([mednafenCoreModule UTF8String], [path UTF8String]);

    if(!game)
        return NO;

    // BGRA pixel format
    MDFN_PixelFormat pix_fmt(MDFN_COLORSPACE_RGB, 16, 8, 0, 24);
    surf = new MDFN_Surface(NULL, game->fb_width, game->fb_height, game->fb_width, pix_fmt);

    masterClock = game->MasterClock >> 32;

    emulation_run();

    return YES;
}

- (void)executeFrame
{
    [self executeFrameSkippingFrame:NO];
}

- (void)executeFrameSkippingFrame: (BOOL) skip
{
    emulation_run();
}

- (void)resetEmulation
{
    MDFNI_Reset();
}

- (void)stopEmulation
{
    MDFNI_CloseGame();
    
    [super stopEmulation];
}

- (NSTimeInterval)frameInterval
{
    return mednafenCoreTiming ?: 60;
}

# pragma mark - Video

- (OEIntRect)screenRect
{
    return OEIntRectMake(videoOffsetX, videoOffsetY, videoWidth, videoHeight);
}

- (OEIntSize)bufferSize
{
    return OEIntSizeMake(game->fb_width, game->fb_height);
}

- (OEIntSize)aspectSize
{
    return mednafenCoreAspect;
}

- (const void *)videoBuffer
{
    return surf->pixels;
}

- (GLenum)pixelFormat
{
    return GL_BGRA;
}

- (GLenum)pixelType
{
    return GL_UNSIGNED_INT_8_8_8_8_REV;
}

- (GLenum)internalPixelFormat
{
    return GL_RGB8;
}

# pragma mark - Audio

static size_t update_audio_batch(const int16_t *data, size_t frames){
    [[current ringBufferAtIndex:0] write:data maxLength:frames * [current channelCount] * 2];
    return frames;
}

- (double)audioSampleRate
{
    return sampleRate ? sampleRate : 48000;
}

- (NSUInteger)channelCount
{
    return game->soundchan;
}

# pragma mark - Save States

size_t mednafen_serialize_size(void)
{
    static size_t serialize_size;

    if (!game->StateAction)
    {
        //NSLog(@"Module doesn't support save states.");
        return 0;
    }

    StateMem st;
    memset(&st, 0, sizeof(st));

    if (!MDFNSS_SaveSM(&st, 0, 1))
    {
        //NSLog(@"Module doesn't support save states.");
        return 0;
    }

    free(st.data);
    return serialize_size = st.len;
}

bool mednafen_serialize(void *data, size_t size)
{
    StateMem st;
    memset(&st, 0, sizeof(st));
    st.data = (uint8_t*)data;
    st.malloced = size;

    return MDFNSS_SaveSM(&st, 0, 1);
}

bool mednafen_unserialize(const void *data, size_t size)
{
    StateMem st;
    memset(&st, 0, sizeof(st));
    st.data = (uint8_t*)data;
    st.len = size;

    return MDFNSS_LoadSM(&st, 0, 1);
}

- (BOOL)saveStateToFileAtPath:(NSString *)fileName
{
    if(current->systemType == psx)
        return NO;
    
    int serial_size = mednafen_serialize_size();
    uint8_t *serial_data = (uint8_t *) malloc(serial_size);
    
    mednafen_serialize(serial_data, serial_size);
    
    FILE *state_file = fopen([fileName UTF8String], "wb");
    long bytes_written = fwrite(serial_data, sizeof(uint8_t), serial_size, state_file);
    
    free(serial_data);
    
    if( bytes_written != serial_size )
    {
        NSLog(@"Couldn't write state");
        return NO;
    }
    fclose( state_file );
    
    return YES;
}

- (BOOL)loadStateFromFileAtPath:(NSString *)fileName
{
    if(current->systemType == psx)
        return NO;
    
    FILE *state_file = fopen([fileName UTF8String], "rb");
    if( !state_file )
    {
        NSLog(@"Could not open state file");
        return NO;
    }
    
    int serial_size = mednafen_serialize_size();
    uint8_t *serial_data = (uint8_t *) malloc(serial_size);
    
    if(!fread(serial_data, sizeof(uint8_t), serial_size, state_file))
    {
        NSLog(@"Couldn't read file");
        return NO;
    }
    fclose(state_file);
    
    if(!mednafen_unserialize(serial_data, serial_size))
    {
        NSLog(@"Couldn't unpack state");
        return NO;
    }
    
    free(serial_data);
    
    return YES;
}

# pragma mark - Input

static int16_t input_state_callback(unsigned port, unsigned device, unsigned index, unsigned id)
{
    //NSLog(@"polled input: port: %d device: %d id: %d", port, device, id);
    if (port == 0 & device == 1) {
        return current->pad[0][id];
    }
    else if(port == 1 & device == 1) {
        return current->pad[1][id];
    }

    return 0;
}

static void update_input()
{
    if(current->systemType == lynx)
    {
        static uint16_t input_buf[2];
        input_buf[0] = input_buf[1] = 0;
        static unsigned map[] = {
            OELynxButtonA,
            OELynxButtonB,
            OELynxButtonOption2,
            OELynxButtonOption1,
            OELynxButtonLeft,
            OELynxButtonRight,
            OELynxButtonUp,
            OELynxButtonDown,
            9, // Pause
        };

        for (unsigned j = 0; j < 1; j++)
        {
            for (unsigned i = 0; i < 9; i++)
                input_buf[j] |= map[i] != -1u &&
                input_state_callback(j, 1, 0, map[i]) ? (1 << i) : 0;
        }

        game->SetInput(0, "gamepad", &input_buf[0]);
    }
    else if(current->systemType == pce)
    {
        static uint16_t input_buf[2];
        input_buf[0] = input_buf[1] = 0;
        static unsigned map[] = {
            OEPCEButton1,
            OEPCEButton2,
            OEPCEButtonSelect,
            OEPCEButtonRun,
            OEPCEButtonUp,
            OEPCEButtonRight,
            OEPCEButtonDown,
            OEPCEButtonLeft,
            OEPCEButton3,  // Button III
            OEPCEButton4, // Button IV
            OEPCEButton5, // Button V
            OEPCEButton6, // Button VI
            OEPCEButtonMode, // 2/6 Mode Select
        };

        for (unsigned j = 0; j < 2; j++)
        {
            for (unsigned i = 0; i < 13; i++)
                input_buf[j] |= map[i] != -1u &&
                input_state_callback(j, 1, 0, map[i]) ? (1 << i) : 0;
        }

        game->SetInput(0, "gamepad", &input_buf[0]);
        game->SetInput(1, "gamepad", &input_buf[1]);
    }
    else if(current->systemType == pcfx)
    {
        static uint16_t input_buf[2];
        input_buf[0] = input_buf[1] = 0;
        static unsigned map[] = {
            OEPCFXButton1,
            OEPCFXButton2,
            OEPCFXButton3,
            OEPCFXButton4,
            OEPCFXButton5,
            OEPCFXButton6,
            OEPCFXButtonSelect,
            OEPCFXButtonRun,
            OEPCFXButtonUp,
            OEPCFXButtonRight,
            OEPCFXButtonDown,
            OEPCFXButtonLeft,
        };

        for (unsigned j = 0; j < 2; j++)
        {
            for (unsigned i = 0; i < 12; i++)
                input_buf[j] |= map[i] != -1u &&
                input_state_callback(j, 1, 0, map[i]) ? (1 << i) : 0;
        }

        game->SetInput(0, "gamepad", &input_buf[0]);
        game->SetInput(1, "gamepad", &input_buf[1]);
    }
    else if(current->systemType == psx)
    {
        union
        {
            uint32_t u32[2][1 + 8];
            uint8_t u8[2][2 * sizeof(uint16_t) + 8 * sizeof(uint32_t)];
        } static buf;

        uint16_t input_buf[2] = {0};
        static unsigned map[] = {
            OEPSXButtonSelect,
            OEPSXButtonL3,
            OEPSXButtonR3,
            OEPSXButtonStart,
            OEPSXButtonUp,
            OEPSXButtonRight,
            OEPSXButtonDown,
            OEPSXButtonLeft,
            OEPSXButtonL2,
            OEPSXButtonR2,
            OEPSXButtonL1,
            OEPSXButtonR1,
            OEPSXButtonTriangle,
            OEPSXButtonCircle,
            OEPSXButtonCross,
            OEPSXButtonSquare,
        };

        for (unsigned j = 0; j < 2; j++)
        {
            for (unsigned i = 0; i < 16; i++)
                input_buf[j] |= input_state_callback(j, 1, 0, map[i]) ? (1 << i) : 0;
        }

        // Buttons.
        buf.u8[0][0] = (input_buf[0] >> 0) & 0xff;
        buf.u8[0][1] = (input_buf[0] >> 8) & 0xff;
        buf.u8[1][0] = (input_buf[1] >> 0) & 0xff;
        buf.u8[1][1] = (input_buf[1] >> 8) & 0xff;

        // Analogs
        for (unsigned j = 0; j < 2; j++)
        {
            int analog_left_x = input_state_callback(j, 5, 0,
                                                     0);

            int analog_left_y = input_state_callback(j, 5, 0,
                                                     1);

            int analog_right_x = input_state_callback(j, 5, 1,
                                                      0);

            int analog_right_y = input_state_callback(j, 5, 1,
                                                      1);

            uint32_t r_right = analog_right_x > 0 ?  analog_right_x : 0;
            uint32_t r_left  = analog_right_x < 0 ? -analog_right_x : 0;
            uint32_t r_down  = analog_right_y > 0 ?  analog_right_y : 0;
            uint32_t r_up    = analog_right_y < 0 ? -analog_right_y : 0;

            uint32_t l_right = analog_left_x > 0 ?  analog_left_x : 0;
            uint32_t l_left  = analog_left_x < 0 ? -analog_left_x : 0;
            uint32_t l_down  = analog_left_y > 0 ?  analog_left_y : 0;
            uint32_t l_up    = analog_left_y < 0 ? -analog_left_y : 0;

            buf.u32[j][1] = r_right;
            buf.u32[j][2] = r_left;
            buf.u32[j][3] = r_down;
            buf.u32[j][4] = r_up;

            buf.u32[j][5] = l_right;
            buf.u32[j][6] = l_left;
            buf.u32[j][7] = l_down;
            buf.u32[j][8] = l_up;
        }

        game->SetInput(0, "gamepad", &buf.u8[0]);
        game->SetInput(1, "gamepad", &buf.u8[1]);
    }
    else if(current->systemType == vb)
    {
        static uint16_t input_buf[2];
        input_buf[0] = input_buf[1] = 0;
        static unsigned map[] = {
            OEVBButtonA,
            OEVBButtonB,
            OEVBButtonR,
            OEVBButtonL,
            OEVBButtonRightUp,
            OEVBButtonRightRight,
            OEVBButtonLeftRight,
            OEVBButtonLeftLeft,
            OEVBButtonLeftDown,
            OEVBButtonLeftUp,
            OEVBButtonStart,
            OEVBButtonSelect,
            OEVBButtonRightLeft,
            OEVBButtonRightDown,
        };

        for (unsigned j = 0; j < 1; j++)
        {
            for (unsigned i = 0; i < 14; i++)
                input_buf[j] |= map[i] != -1u &&
                input_state_callback(j, 1, 0, map[i]) ? (1 << i) : 0;
        }

        game->SetInput(0, "gamepad", &input_buf[0]);
    }
    else if(current->systemType == wswan)
    {
        static uint16_t input_buf[2];
        input_buf[0] = input_buf[1] = 0;
        static unsigned map[] = {
            OEWSButtonX1, //X Cursor horizontal-layout games
            OEWSButtonX2, //X Cursor horizontal-layout games
            OEWSButtonX3, //X Cursor horizontal-layout games
            OEWSButtonX4, //X Cursor horizontal-layout games
            OEWSButtonY1, //Y Cursor UP vertical-layout games
            OEWSButtonY2, //Y Cursor RIGHT vertical-layout games
            OEWSButtonY3, //Y Cursor DOWN vertical-layout games
            OEWSButtonY4, //Y Cursor LEFT vertical-layout games
            OEWSButtonStart,
            OEWSButtonA,
            OEWSButtonB,
        };

        for (unsigned j = 0; j < 1; j++)
        {
            for (unsigned i = 0; i < 11; i++)
                input_buf[j] |= map[i] != -1u &&
                input_state_callback(j, 1, 0, map[i]) ? (1 << i) : 0;
        }
        
        game->SetInput(0, "gamepad", &input_buf[0]);
    }
}

NSUInteger LynxEmulatorValues[] = { OELynxButtonUp, OELynxButtonDown, OELynxButtonLeft, OELynxButtonRight, OELynxButtonA, OELynxButtonB, OELynxButtonOption1, OELynxButtonOption2 };

NSUInteger PCEEmulatorValues[] = { OEPCEButtonUp, OEPCEButtonDown, OEPCEButtonLeft, OEPCEButtonRight, OEPCEButton1, OEPCEButton2, OEPCEButton3, OEPCEButton4, OEPCEButton5, OEPCEButton6, OEPCEButtonRun, OEPCEButtonSelect, OEPCEButtonMode };

NSUInteger PCFXEmulatorValues[] = { OEPCFXButtonUp, OEPCFXButtonDown, OEPCFXButtonLeft, OEPCFXButtonRight, OEPCFXButton1, OEPCFXButton2, OEPCFXButton3, OEPCFXButton4, OEPCFXButton5, OEPCFXButton6, OEPCFXButtonRun, OEPCFXButtonSelect };

NSUInteger PSXEmulatorValues[] = { OEPSXButtonUp, OEPSXButtonDown, OEPSXButtonLeft, OEPSXButtonRight, OEPSXButtonTriangle, OEPSXButtonCircle, OEPSXButtonCross, OEPSXButtonSquare, OEPSXButtonL1, OEPSXButtonL2, OEPSXButtonL3, OEPSXButtonR1, OEPSXButtonR2, OEPSXButtonR3, OEPSXButtonStart, OEPSXButtonSelect };

NSUInteger VBEmulatorValues[] = { OEVBButtonLeftUp, OEVBButtonLeftDown, OEVBButtonLeftLeft, OEVBButtonLeftRight, OEVBButtonRightUp, OEVBButtonRightDown, OEVBButtonRightLeft, OEVBButtonRightRight,OEVBButtonL, OEVBButtonR, OEVBButtonA, OEVBButtonB, OEVBButtonStart, OEVBButtonSelect };

NSUInteger WSEmulatorValues[] = { OEWSButtonX1, OEWSButtonX3, OEWSButtonX4, OEWSButtonX2, OEWSButtonY1, OEWSButtonY3, OEWSButtonY4, OEWSButtonY2, OEWSButtonA, OEWSButtonB, OEWSButtonStart, OEWSButtonSound };

- (oneway void)didPushLynxButton:(OELynxButton)button forPlayer:(NSUInteger)player;
{
    pad[player-1][LynxEmulatorValues[button]] = 1;
}

- (oneway void)didReleaseLynxButton:(OELynxButton)button forPlayer:(NSUInteger)player;
{
    pad[player-1][LynxEmulatorValues[button]] = 0;
}

- (oneway void)didPushPCEButton:(OEPCEButton)button forPlayer:(NSUInteger)player;
{
    pad[player-1][PCEEmulatorValues[button]] = 1;
}

- (oneway void)didReleasePCEButton:(OEPCEButton)button forPlayer:(NSUInteger)player;
{
    pad[player-1][PCEEmulatorValues[button]] = 0;
}

- (oneway void)didPushPCFXButton:(OEPCFXButton)button forPlayer:(NSUInteger)player;
{
    pad[player-1][PCFXEmulatorValues[button]] = 1;
}

- (oneway void)didReleasePCFXButton:(OEPCFXButton)button forPlayer:(NSUInteger)player;
{
    pad[player-1][PCFXEmulatorValues[button]] = 0;
}

- (oneway void)didPushPSXButton:(OEPSXButton)button forPlayer:(NSUInteger)player;
{
    pad[player-1][PSXEmulatorValues[button]] = 1;
}

- (oneway void)didReleasePSXButton:(OEPSXButton)button forPlayer:(NSUInteger)player;
{
    pad[player-1][PSXEmulatorValues[button]] = 0;
}

- (oneway void)didPushVBButton:(OEVBButton)button forPlayer:(NSUInteger)player;
{
    pad[player-1][VBEmulatorValues[button]] = 1;
}

- (oneway void)didReleaseVBButton:(OEVBButton)button forPlayer:(NSUInteger)player;
{
    pad[player-1][VBEmulatorValues[button]] = 0;
}

- (oneway void)didPushWSButton:(OEWSButton)button forPlayer:(NSUInteger)player;
{
    pad[player-1][WSEmulatorValues[button]] = 1;
}

- (oneway void)didReleaseWSButton:(OEWSButton)button forPlayer:(NSUInteger)player;
{
    pad[player-1][WSEmulatorValues[button]] = 0;
}

@end
