{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Komposition.UserInterface.GtkInterface.RangeSlider where

import           Komposition.Prelude

import           Data.Vector                    (Vector)
import qualified GI.GObject                     as GI
import qualified GI.Gtk                         as Gtk
import           GI.Gtk.Declarative
import           GI.Gtk.Declarative.EventSource

type CustomState = ()

data RangeSliderProperties = RangeSliderProperties
  { range      :: (Double, Double)
  , rangeValue :: Double
  } deriving (Eq, Show)


newtype RangeSliderEvent = RangeSliderChanged Double

rangeSlider
  :: Vector (Attribute Gtk.Scale RangeSliderEvent)
  -> RangeSliderProperties
  -> Widget RangeSliderEvent
rangeSlider customAttributes customParams = Widget (
  CustomWidget
    { customWidget = Gtk.Scale
    , customCreate = \RangeSliderProperties { range, rangeValue } -> do
        scale <- Gtk.new Gtk.Scale []
        uncurry (#setRange scale) range
        #setValue scale rangeValue
        Gtk.scaleSetDrawValue scale False
        return (scale, ())

    , customPatch = \old new () ->
        if old == new
        then CustomKeep
        else CustomModify $ \scale -> do
          uncurry (#setRange scale) (range new)
          return ()

    , customSubscribe = \_ _ (scale :: Gtk.Scale) cb -> do
        h <- Gtk.on scale
                    #valueChanged
                    (cb . RangeSliderChanged =<< #getValue scale)
        return (fromCancellation (GI.signalHandlerDisconnect scale h))
    , ..
})
