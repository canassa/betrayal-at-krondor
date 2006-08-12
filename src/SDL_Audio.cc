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
 * Copyright (C) 2005-2006  Guido de Jong <guidoj@users.sf.net>
 */

#include "SDL.h"
#include "SDL_mixer.h"
#include "SDL_sound.h"

#include "Exception.h"
#include "SDL_Audio.h"

static const unsigned int AUDIO_FREQUENCY       = 11025;
static const unsigned int AUDIO_FORMAT          = AUDIO_U8;
static const unsigned int AUDIO_STEREO          = 2;
static const unsigned int AUDIO_CHANNELS        = 8;
static const unsigned int AUDIO_BUFFER_SIZE     = 4096;
static const unsigned int AUDIO_RAW_BUFFER_SIZE = 16384;

SDL_mutex    *audioMutex;
Sound_Sample *audioSample[AUDIO_CHANNELS];

void
ChannelDone(int channel)
{
  Mix_FreeChunk(Mix_GetChunk(channel));
  SDL_LockMutex(audioMutex);
  if (audioSample[channel]) {
    Sound_FreeSample(audioSample[channel]);
  }
  SDL_UnlockMutex(audioMutex);
}

SDL_Audio::SDL_Audio()
{
  memset(audioSample, 0, sizeof(audioSample));
  audioMutex = SDL_CreateMutex();
  if (!audioMutex) {
    throw SDL_Exception(__FILE__, __LINE__, SDL_GetError());
  }
  if (!Sound_Init()) {
    throw SDL_Exception(__FILE__, __LINE__, Sound_GetError());
  }
  if (Mix_OpenAudio(AUDIO_FREQUENCY, AUDIO_FORMAT, AUDIO_STEREO, AUDIO_BUFFER_SIZE) < 0)
  {
    throw SDL_Exception(__FILE__, __LINE__, Mix_GetError());
  }
  Mix_AllocateChannels(AUDIO_CHANNELS);
  Mix_ChannelFinished(ChannelDone);
  if (Mix_VolumeMusic(90) < 0)
  {
    throw SDL_Exception(__FILE__, __LINE__, Mix_GetError());
  }
}

SDL_Audio::~SDL_Audio()
{
  Mix_HaltChannel(-1);
  Mix_CloseAudio();
  if (!Sound_Quit()) {
    throw SDL_Exception(__FILE__, __LINE__, Sound_GetError());
  }
  if (audioMutex)
  {
    SDL_DestroyMutex(audioMutex);
  }
}

int
SDL_Audio::PlaySound(FileBuffer *buffer, const int repeat)
{
  static Sound_AudioInfo info = {AUDIO_FORMAT, AUDIO_STEREO, AUDIO_FREQUENCY};
  buffer->Rewind();
  SDL_RWops *rwops = SDL_RWFromMem(buffer->GetCurrent(), buffer->GetSize());
  if (!rwops) {
    throw SDL_Exception(__FILE__, __LINE__, SDL_GetError());
  }
  Sound_Sample *sample = Sound_NewSample(rwops, 0, &info, AUDIO_RAW_BUFFER_SIZE);
  if (!sample) {
    throw SDL_Exception(__FILE__, __LINE__, Sound_GetError());
  }
  unsigned int decoded = Sound_DecodeAll(sample);
  if (sample->flags & SOUND_SAMPLEFLAG_ERROR) {
    throw SDL_Exception(__FILE__, __LINE__, Sound_GetError());
  }
  Mix_Chunk *chunk = Mix_QuickLoad_RAW((Uint8*)sample->buffer, decoded);
  if (!chunk) {
    throw SDL_Exception(__FILE__, __LINE__, Mix_GetError());
  }
  int channel = Mix_PlayChannel(-1, chunk, repeat);
  if (channel < 0) {
    throw SDL_Exception(__FILE__, __LINE__, Mix_GetError());
  }
  SDL_LockMutex(audioMutex);
  audioSample[channel] = sample;
  SDL_UnlockMutex(audioMutex);
  return channel;
}

void
SDL_Audio::StopSound(const int channel)
{
  Mix_HaltChannel(channel);
}
