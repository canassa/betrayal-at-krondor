cmake_minimum_required(VERSION 3.13)
project(xbak)

find_package(SDL REQUIRED)
find_package(SDL_MIXER REQUIRED)
find_package(SDL_SOUND REQUIRED)

include_directories(${SDL_INCLUDE_DIR})
include_directories(${SDL_MIXER_INCLUDE_DIR})
include_directories(${SDL_SOUND_INCLUDE_DIR})

set(CMAKE_CXX_STANDARD 14)

set(
    SOURCES
    src/AnimationResource.cc
    src/AnimationResource.h
    src/Audio.h src/BMP.cc
    src/BMP.h
    src/BadgeWidget.cc
    src/BadgeWidget.h
    src/BasicFile.cc
    src/BasicFile.h
    src/BookResource.cc
    src/BookResource.h
    src/ButtonWidget.cc
    src/ButtonWidget.h
    src/Camera.cc
    src/Camera.h
    src/Chapter.cc
    src/Chapter.h
    src/CharacterButtonWidget.cc
    src/CharacterButtonWidget.h
    src/ChoiceWidget.cc
    src/ChoiceWidget.h
    src/Clock.h
    src/CombatViewWidget.cc
    src/CombatViewWidget.h
    src/CompassWidget.cc
    src/CompassWidget.h
    src/ConfigData.h
    src/ConfigFile.cc
    src/ConfigFile.h
    src/ConfigResource.cc
    src/ConfigResource.h
    src/ContainerWidget.cc
    src/ContainerWidget.h
    src/Defines.h
    src/Dialog.cc
    src/Dialog.h
    src/DialogFactory.cc
    src/DialogFactory.h
    src/DialogResource.cc
    src/DialogResource.h
    src/DialogWindow.cc
    src/DialogWindow.h
    src/Directories.cc
    src/Directories.h
    src/EquipmentItemWidget.cc
    src/EquipmentItemWidget.h
    src/EquipmentWidget.cc
    src/EquipmentWidget.h
    src/Event.cc
    src/Event.h
    src/EventListener.h
    src/Exception.cc
    src/Exception.h
    src/FileBuffer.cc
    src/FileBuffer.h
    src/FileManager.cc
    src/FileManager.h
    src/Font.cc
    src/Font.h
    src/FontResource.cc
    src/FontResource.h
    src/Game.cc
    src/Game.h
    src/GameApplication.cc
    src/GameApplication.h
    src/GameData.h
    src/GameFile.cc
    src/GameFile.h
    src/GameResource.cc
    src/GameResource.h
    src/GameState.cc
    src/GameState.h
    src/GameViewWidget.cc
    src/GameViewWidget.h
    src/GenericObject.cc
    src/GenericObject.h
    src/Geometry.cc
    src/Geometry.h
    src/HotspotWidget.cc
    src/HotspotWidget.h
    src/Image.cc
    src/Image.h
    src/ImageButtonWidget.cc
    src/ImageButtonWidget.h
    src/ImageResource.cc
    src/ImageResource.h
    src/ImageWidget.cc
    src/ImageWidget.h
    src/Inventory.cc
    src/Inventory.h
    src/InventoryItem.cc
    src/InventoryItem.h
    src/InventoryItemWidget.cc
    src/InventoryItemWidget.h
    src/InventoryWidget.cc
    src/InventoryWidget.h
    src/LabelResource.cc
    src/LabelResource.h
    src/MapViewWidget.cc
    src/MapViewWidget.h
    src/MediaToolkit.cc
    src/MediaToolkit.h
    src/MoviePlayer.cc
    src/MoviePlayer.h
    src/MovieResource.cc
    src/MovieResource.h
    src/NameResource.cc
    src/NameResource.h
    src/Null_Audio.cc
    src/Null_Audio.h
    src/ObjectResource.cc
    src/ObjectResource.h
    src/Observer.h
    src/Orientation.cc
    src/Orientation.h
    src/Palette.cc
    src/Palette.h
    src/PaletteResource.cc
    src/PaletteResource.h
    src/PanelWidget.cc
    src/PanelWidget.h
    src/Party.cc
    src/Party.h
    src/PartyResource.cc
    src/PartyResource.h
    src/PatternPolygonObject.cc
    src/PatternPolygonObject.h
    src/PlayerCharacter.cc
    src/PlayerCharacter.h
    src/Pointer.cc
    src/Pointer.h
    src/PointerManager.cc
    src/PointerManager.h
    src/PolygonObject.cc
    src/PolygonObject.h
    src/PopUpWidget.cc
    src/PopUpWidget.h
    src/PortraitWidget.cc
    src/PortraitWidget.h
    src/Position.cc
    src/Position.h
    src/Preferences.cc
    src/Preferences.h
    src/PreferencesDialogBridge.cc
    src/PreferencesDialogBridge.h
    src/RampResource.cc
    src/RampResource.h
    src/RatingsWidget.cc
    src/RatingsWidget.h
    src/RequestResource.cc
    src/RequestResource.h
    src/ResourceArchive.cc
    src/ResourceArchive.h
    src/ResourceData.h
    src/ResourceFile.cc
    src/ResourceFile.h
    src/ResourceIndex.cc
    src/ResourceIndex.h
    src/ResourceTag.cc
    src/ResourceTag.h
    src/SDL_Audio.cc
    src/SDL_Audio.h
    src/SDL_Clock.cc
    src/SDL_Clock.h
    src/SDL_Toolkit.cc
    src/SDL_Toolkit.h
    src/SDL_Video.cc
    src/SDL_Video.h
    src/Scene.cc
    src/Scene.h
    src/SceneFactory.cc
    src/SceneFactory.h
    src/ScreenResource.cc
    src/ScreenResource.h
    src/SkillLevelWidget.cc
    src/SkillLevelWidget.h
    src/SkillsWidget.cc
    src/SkillsWidget.h
    src/SolidPolygonObject.cc
    src/SolidPolygonObject.h
    src/Sound.cc
    src/Sound.h
    src/SoundResource.cc
    src/SoundResource.h
    src/SpriteObject.cc
    src/SpriteObject.h
    src/Statistics.cc
    src/Statistics.h
    src/Subject.cc
    src/Subject.h
    src/TableResource.cc
    src/TableResource.h
    src/TaggedImageResource.cc
    src/TaggedImageResource.h
    src/TaggedResource.cc
    src/TaggedResource.h
    src/TestApplication.cc
    src/TestApplication.h
    src/Text.cc
    src/Text.h
    src/TextButtonWidget.cc
    src/TextButtonWidget.h
    src/TextWidget.cc
    src/TextWidget.h
    src/TileDataResource.cc
    src/TileDataResource.h
    src/TileWorldResource.cc
    src/TileWorldResource.h
    src/Vertex.cc
    src/Vertex.h
    src/Video.cc
    src/Video.h
    src/Widget.cc
    src/Widget.h
    src/WidgetFactory.cc
    src/WidgetFactory.h
    src/WorldViewWidget.cc
    src/WorldViewWidget.h
    src/Zone.cc
    src/Zone.h
    src/alt_stdint.h
)

add_executable(${PROJECT_NAME} src/xbak.cc ${SOURCES})
target_link_libraries(${PROJECT_NAME} ${SDL_LIBRARY} ${SDL_MIXER_LIBRARIES} ${SDL_SOUND_LIBRARIES})

add_executable(convertresource src/convertresource.cc ${SOURCES})
target_link_libraries(convertresource ${SDL_LIBRARY} ${SDL_MIXER_LIBRARIES} ${SDL_SOUND_LIBRARIES})

add_executable(dumpads src/dumpads.cc ${SOURCES})
target_link_libraries(dumpads ${SDL_LIBRARY} ${SDL_MIXER_LIBRARIES} ${SDL_SOUND_LIBRARIES})

add_executable(dumpbmx src/dumpbmx.cc ${SOURCES})
target_link_libraries(dumpbmx ${SDL_LIBRARY} ${SDL_MIXER_LIBRARIES} ${SDL_SOUND_LIBRARIES})

add_executable(dumpbok src/dumpbok.cc ${SOURCES})
target_link_libraries(dumpbok ${SDL_LIBRARY} ${SDL_MIXER_LIBRARIES} ${SDL_SOUND_LIBRARIES})

add_executable(dumpddx src/dumpddx.cc ${SOURCES})
target_link_libraries(dumpddx ${SDL_LIBRARY} ${SDL_MIXER_LIBRARIES} ${SDL_SOUND_LIBRARIES})

add_executable(dumpfnt src/dumpfnt.cc ${SOURCES})
target_link_libraries(dumpfnt ${SDL_LIBRARY} ${SDL_MIXER_LIBRARIES} ${SDL_SOUND_LIBRARIES})

add_executable(dumpgam src/dumpgam.cc ${SOURCES})
target_link_libraries(dumpgam ${SDL_LIBRARY} ${SDL_MIXER_LIBRARIES} ${SDL_SOUND_LIBRARIES})

add_executable(dumplbl src/dumplbl.cc ${SOURCES})
target_link_libraries(dumplbl ${SDL_LIBRARY} ${SDL_MIXER_LIBRARIES} ${SDL_SOUND_LIBRARIES})

add_executable(dumpobj src/dumpobj.cc ${SOURCES})
target_link_libraries(dumpobj ${SDL_LIBRARY} ${SDL_MIXER_LIBRARIES} ${SDL_SOUND_LIBRARIES})

add_executable(dumppal src/dumppal.cc ${SOURCES})
target_link_libraries(dumppal ${SDL_LIBRARY} ${SDL_MIXER_LIBRARIES} ${SDL_SOUND_LIBRARIES})

add_executable(dumpreq src/dumpreq.cc ${SOURCES})
target_link_libraries(dumpreq ${SDL_LIBRARY} ${SDL_MIXER_LIBRARIES} ${SDL_SOUND_LIBRARIES})

add_executable(dumpscx src/dumpscx.cc ${SOURCES})
target_link_libraries(dumpscx ${SDL_LIBRARY} ${SDL_MIXER_LIBRARIES} ${SDL_SOUND_LIBRARIES})

add_executable(dumpsnd src/dumpsnd.cc ${SOURCES})
target_link_libraries(dumpsnd ${SDL_LIBRARY} ${SDL_MIXER_LIBRARIES} ${SDL_SOUND_LIBRARIES})

add_executable(dumptbl src/dumptbl.cc ${SOURCES})
target_link_libraries(dumptbl ${SDL_LIBRARY} ${SDL_MIXER_LIBRARIES} ${SDL_SOUND_LIBRARIES})

add_executable(dumpttm src/dumpttm.cc ${SOURCES})
target_link_libraries(dumpttm ${SDL_LIBRARY} ${SDL_MIXER_LIBRARIES} ${SDL_SOUND_LIBRARIES})

add_executable(dumpwld src/dumpwld.cc ${SOURCES})
target_link_libraries(dumpwld ${SDL_LIBRARY} ${SDL_MIXER_LIBRARIES} ${SDL_SOUND_LIBRARIES})

add_executable(resourcedemo src/resourcedemo.cc ${SOURCES})
target_link_libraries(resourcedemo ${SDL_LIBRARY} ${SDL_MIXER_LIBRARIES} ${SDL_SOUND_LIBRARIES})
