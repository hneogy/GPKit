"""pygpkit: GPKit from Python.

GPKit reads GP data (OMM as CSV, JSON, XML or KVN, and TLE with Alpha-5), writes TLE, propagates with SGP4, and finds
passes over a place. pygpkit is GPKit itself, compiled, behind a small C interface: every number it gives is the one
GPKit's own release build gives on the same system, to the bit, which the package's tests hold it to.

    import pygpkit
    file = pygpkit.read("iss.tle")
    iss = file.element_sets[0]
    propagator = pygpkit.Propagator(iss)
    home = pygpkit.Observer(40.0, -75.0)
    for p in propagator.passes(home, start=iss.epoch, seconds=86_400, above=10):
        print(p.rise.time, round(p.culmination.look.elevation))

Times are UTC, as text in the CCSDS form ``2026-11-06T12:00:00.000000`` or as timezone-aware ``datetime`` values.
"""

from __future__ import annotations

import base64
import ctypes
import datetime as _datetime
import json
import os
import sys
from dataclasses import dataclass
from typing import Any, Iterable, Optional, Sequence, Tuple, Union

__all__ = [
    "read", "ElementSet", "ElementSetFile", "Propagator", "Observer", "State", "Look", "GeodeticPosition", "Pass",
    "Event", "PassSearch", "Refusal", "PropagationFailure",
]
__version__ = "0.1.0"


def _library_name() -> str:
    if sys.platform == "darwin":
        return "libpygpkit_core.dylib"
    if sys.platform == "win32":
        return "pygpkit_core.dll"
    return "libpygpkit_core.so"


def _load() -> ctypes.CDLL:
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.environ.get("PYGPKIT_LIBRARY") or os.path.join(here, _library_name())
    library = ctypes.CDLL(path)
    library.pygpkit_call.argtypes = [ctypes.c_char_p]
    library.pygpkit_call.restype = ctypes.c_void_p
    library.pygpkit_free.argtypes = [ctypes.c_void_p]
    library.pygpkit_free.restype = None
    return library


_library = _load()


def _call(request: dict) -> dict:
    pointer = _library.pygpkit_call(json.dumps(request).encode("utf-8"))
    try:
        answer = json.loads(ctypes.string_at(pointer).decode("utf-8"))
    finally:
        _library.pygpkit_free(pointer)
    if "error" in answer:
        raise ValueError(answer["error"])
    return answer


def _epoch(time: Union[str, _datetime.datetime]) -> str:
    """An instant as GPKit reads it: CCSDS text as it is, an aware datetime turned to UTC."""
    if isinstance(time, str):
        return time
    if isinstance(time, _datetime.datetime):
        if time.tzinfo is None or time.utcoffset() is None:
            raise ValueError("a datetime without a time zone is not taken for UTC: give it tzinfo=datetime.timezone.utc")
        return time.astimezone(_datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")
    raise TypeError("a time is CCSDS text or an aware datetime")


class Refusal(Exception):
    """GPKit would not read or write something, and says why: its kind (one of GPKit's Refusal.Kind), a message, and
    where."""

    def __init__(self, fields: dict):
        super().__init__(fields["description"])
        self.kind: str = fields["kind"]
        self.message: str = fields["message"]
        self.field: Optional[str] = fields["field"]
        self.text: Optional[str] = fields["text"]
        self.catalog_field: Optional[str] = fields["catalog_field"]
        self.record: Optional[int] = fields["record"]
        self.line: Optional[int] = fields["line"]


class PropagationFailure(Exception):
    """SGP4 could not go on: its kind (one of GPKit's PropagationFailure.Kind) and the minutes from the epoch at
    which it stopped, None when it never began."""

    def __init__(self, fields: dict):
        super().__init__(fields["description"])
        self.kind: str = fields["kind"]
        self.minutes_from_epoch: Optional[float] = fields["minutes_from_epoch"]


class _Handle:
    """A value held in the native library, released when this object goes."""

    _id: int

    def __del__(self):
        try:
            _call({"op": "release", "ids": [self._id]})
        except Exception:
            pass


class ElementSet(_Handle):
    """One element set as GPKit read it. The elements are text, exactly as read (GPKit's ExactDecimal); the epoch is
    CCSDS text, UTC."""

    def __init__(self, handle: int, fields: dict):
        self._id = handle
        self.fields: dict = fields
        self.catalog_number: Optional[int] = fields["catalog_number"]
        self.object_name: Optional[str] = fields["object_name"]
        self.object_id: Optional[str] = fields["object_id"]
        self.epoch: str = fields["epoch"]

    def __getattr__(self, name: str) -> Any:
        try:
            return self.__dict__["fields"][name]
        except KeyError:
            raise AttributeError(name) from None

    def __repr__(self) -> str:
        return f"ElementSet({self.object_name!r}, catalog number {self.catalog_number}, epoch {self.epoch})"

    def to_tle(self, eccentricity: str = "rounded") -> Tuple[Optional[str], str, str]:
        """The set written as a TLE: (name or None, line 1, line 2). ``eccentricity="truncated"`` cuts the
        eccentricity off, as CelesTrak writes it. Raises Refusal when the set cannot be written as a TLE."""
        answer = _call({"op": "tle", "set": self._id, "eccentricity": eccentricity})
        if "refusal" in answer:
            raise Refusal(answer["refusal"])
        return answer["name"], answer["line1"], answer["line2"]


@dataclass(frozen=True)
class ElementSetFile:
    """What reading a file gave: its records in order, each an ElementSet or a Refusal."""

    entries: Tuple[Union[ElementSet, Refusal], ...]
    provider_message: Optional[str]

    @property
    def element_sets(self) -> Tuple[ElementSet, ...]:
        return tuple(e for e in self.entries if isinstance(e, ElementSet))

    @property
    def refusals(self) -> Tuple[Refusal, ...]:
        return tuple(e for e in self.entries if isinstance(e, Refusal))


_FORMATS = {".csv": "csv", ".json": "json", ".xml": "xml", ".kvn": "kvn", ".tle": "tle", ".txt": "tle"}


def read(source: Union[str, os.PathLike, bytes], format: Optional[str] = None, checksum: bool = True) -> ElementSetFile:
    """Reads GP data: a path, or the file's bytes with ``format`` ("csv", "json", "xml", "kvn" or "tle"). A path's
    extension gives its format unless ``format`` does. ``checksum=False`` reads TLE lines whatever their checksum.
    Raises Refusal when the whole file is refused; a refused record is among the entries."""
    if isinstance(source, bytes):
        data = source
        if format is None:
            raise ValueError("bytes need a format: csv, json, xml, kvn or tle")
    else:
        path = os.fspath(source)
        with open(path, "rb") as f:
            data = f.read()
        if format is None:
            format = _FORMATS.get(os.path.splitext(path)[1].lower())
            if format is None:
                raise ValueError(f"{path}: the extension does not say the format; give format=")
    answer = _call({"op": "read", "data": base64.b64encode(data).decode("ascii"), "format": format, "checksum": checksum})
    if "refusal" in answer:
        raise Refusal(answer["refusal"])
    entries = tuple(ElementSet(e["set"], e["fields"]) if "set" in e else Refusal(e["refusal"]) for e in answer["entries"])
    return ElementSetFile(entries, answer["provider_message"])


@dataclass(frozen=True)
class Observer:
    """A place on the WGS-84 ellipsoid: geodetic latitude and longitude in degrees (north and east positive), and
    height above the ellipsoid in metres."""

    latitude: float
    longitude: float
    height: float = 0.0

    def _json(self) -> list:
        return [self.latitude, self.longitude, self.height]


@dataclass(frozen=True)
class State:
    """Position (km) and velocity (km/s) in TEME."""

    position: Tuple[float, float, float]
    velocity: Tuple[float, float, float]


@dataclass(frozen=True)
class Look:
    """Where a satellite is from a place: azimuth and elevation in degrees (geometric), range in km, range rate in
    km/s (positive while it draws away)."""

    azimuth: float
    elevation: float
    range: float
    range_rate: float

    def received(self, transmitted: float) -> float:
        """The frequency a signal sent on ``transmitted`` arrives at here, by GPKit's formula."""
        return transmitted * (1.0 - self.range_rate / 299_792.458)


@dataclass(frozen=True)
class GeodeticPosition:
    """The point of the WGS-84 ellipsoid beneath the satellite, degrees, and its height above it, km."""

    latitude: float
    longitude: float
    altitude: float


@dataclass(frozen=True)
class Event:
    time: str
    look: Look


@dataclass(frozen=True)
class Pass:
    """One pass: rise and set are None for a pass under way at the search's start or end."""

    rise: Optional[Event]
    culmination: Event
    set: Optional[Event]


@dataclass(frozen=True)
class PassSearch:
    """The passes found, in order, and the failure that stopped the search early, if one did. Iterating gives the
    passes."""

    passes: Tuple[Pass, ...]
    failure: Optional[PropagationFailure]

    def __iter__(self):
        return iter(self.passes)

    def __len__(self) -> int:
        return len(self.passes)


def _state(v: dict) -> State:
    return State(tuple(v["position"]), tuple(v["velocity"]))


def _look(v: dict) -> Look:
    return Look(v["azimuth"], v["elevation"], v["range"], v["range_rate"])


def _event(v: Optional[dict]) -> Optional[Event]:
    return None if v is None else Event(v["time"], _look(v["look"]))


class Propagator(_Handle):
    """SGP4 for one element set, GPKit's port of Vallado's SGP4. ``gravity`` is "wgs72" (the default, as the
    element sets are fitted with), "wgs84" or "wgs72old". Raises PropagationFailure when the set cannot be
    propagated at all."""

    def __init__(self, element_set: ElementSet, gravity: str = "wgs72"):
        answer = _call({"op": "propagator", "set": element_set._id, "gravity": gravity})
        if "failure" in answer:
            raise PropagationFailure(answer["failure"])
        self._id = answer["propagator"]
        self.element_set = element_set

    def _results(self, op: str, times: Sequence, extra: Optional[dict] = None) -> list:
        request = {"op": op, "propagator": self._id, "times": [_epoch(t) for t in times]}
        request.update(extra or {})
        return _call(request)["results"]

    @staticmethod
    def _one(result: dict, make):
        if "failure" in result:
            raise PropagationFailure(result["failure"])
        return make(result["value"])

    def state(self, time: Union[str, _datetime.datetime]) -> State:
        """The state at an instant of UTC."""
        return self._one(self._results("state", [time])[0], _state)

    def states(self, times: Iterable) -> list:
        """The state at each instant: a State, or the PropagationFailure for that instant, in place."""
        return [PropagationFailure(r["failure"]) if "failure" in r else _state(r["value"]) for r in self._results("state", list(times))]

    def state_at_minutes(self, minutes: float) -> State:
        """The state a number of minutes from the element set's epoch."""
        return self._one(_call({"op": "state", "propagator": self._id, "minutes": [minutes]})["results"][0], _state)

    def look(self, observer: Observer, time: Union[str, _datetime.datetime]) -> Look:
        """The satellite as seen from a place at an instant."""
        return self._one(self._results("look", [time], {"observer": observer._json()})[0], _look)

    def position(self, time: Union[str, _datetime.datetime]) -> GeodeticPosition:
        """The point beneath the satellite at an instant, and its height."""
        return self._one(self._results("position", [time])[0], lambda v: GeodeticPosition(v["latitude"], v["longitude"], v["altitude"]))

    def passes(self, observer: Observer, start: Union[str, _datetime.datetime], seconds: float, above: float = 0.0) -> PassSearch:
        """The passes over a place from ``start`` for ``seconds``, counted from ``above`` degrees of elevation."""
        answer = _call({"op": "passes", "propagator": self._id, "observer": observer._json(), "start": _epoch(start),
                        "seconds": seconds, "above": above})
        passes = tuple(Pass(_event(p["rise"]), _event(p["culmination"]), _event(p["set"])) for p in answer["passes"])
        failure = None if answer["failure"] is None else PropagationFailure(answer["failure"])
        return PassSearch(passes, failure)
