/*
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or (at
 * your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE, GOOD TITLE or
 * NON INFRINGEMENT.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 * Copyright (C) 2005-2007  Guido de Jong <guidoj@users.sf.net>
 */

#ifndef SOUND_H
#define SOUND_H

#include <map>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "FileBuffer.h"

typedef enum _SoundFormat {
    SF_MIDI,
    SF_WAVE,
    SF_UNKNOWN
} SoundFormat;

struct MidiEvent
{
    unsigned int delta;
    unsigned int size;
    uint8_t data[8];
};

class Sound
{
private:
    unsigned int type;
    unsigned int channel;
    SoundFormat format;
    FileBuffer *buffer;
    std::multimap<unsigned int, MidiEvent> midiEvents;
    void PutVariableLength ( FileBuffer *buf, unsigned int n );
    void CreateWaveSamples ( FileBuffer *buf );
    void CreateMidiEvents ( FileBuffer *buf );
    void GenerateMidi();
    void GenerateWave();
public:
    Sound ( const unsigned int t );
    virtual ~Sound();
    unsigned int GetType() const;
    unsigned int GetChannel() const;
    SoundFormat GetFormat() const;
    FileBuffer * GetSamples();
    void AddVoice ( FileBuffer *buf );
    void GenerateBuffer();
};

#endif
