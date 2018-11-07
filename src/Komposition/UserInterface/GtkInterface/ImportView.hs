{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE GADTs             #-}
{-# LANGUAGE OverloadedLabels  #-}
{-# LANGUAGE OverloadedLists   #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

-- | The import view of Komposition's GTK interface.
module Komposition.UserInterface.GtkInterface.ImportView
  ( importView
  ) where

import           Komposition.Prelude       hiding (State, on)

import           GI.Gtk                (Box (..), Button (..), CheckButton (..),
                                        FileChooserButton (..),
                                        Orientation (..), Window (..),
                                        fileChooserGetFilename,
                                        toggleButtonGetActive)
import           GI.Gtk.Declarative    as Gtk

import           Komposition.UserInterface hiding (importView, Window)

importView :: ImportFileModel -> Bin Window Widget (Event ImportMode)
importView ImportFileModel {..} =
  bin
    Window
    [ #title := "Import File"
    , on #deleteEvent (const (True, WindowClosed))
    , #defaultWidth := 300
    ] $
  container Box [classes ["import-view"], #orientation := OrientationVertical] $ do
    boxChild False False 10 $
      widget
        FileChooserButton
        [ onM
            #selectionChanged
            (fmap ImportFileSelected . fileChooserGetFilename)
        ]
    boxChild False False 10 $
      widget
        CheckButton
        [ #label := "Classify parts automatically"
        , #active := autoSplitValue
        , #sensitive := autoSplitAvailable
        , onM #toggled (fmap ImportAutoSplitSet . toggleButtonGetActive)
        ]
    boxChild False False 10 $
      widget Button [#label := "Import", on #clicked ImportClicked]
