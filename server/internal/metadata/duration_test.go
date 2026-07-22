package metadata

import (
	"bytes"
	"encoding/binary"
	"errors"
	"testing"
	"time"
)

func TestReadDurationFLAC(t *testing.T) {
	data := testFLACStreamInfo(4 * time.Second)

	duration, format, err := ReadDuration(bytes.NewReader(data))
	if err != nil {
		t.Fatalf("ReadDuration returned error: %v", err)
	}
	if format != "flac" {
		t.Fatalf("format = %q, want flac", format)
	}
	if duration != 4*time.Second {
		t.Fatalf("duration = %s, want 4s", duration)
	}
}

func TestReadDurationMP3Frames(t *testing.T) {
	header := []byte{0xff, 0xfb, 0x90, 0x64}
	frameSize := 417
	data := make([]byte, frameSize*2)
	copy(data, header)
	copy(data[frameSize:], header)

	duration, format, err := ReadDuration(bytes.NewReader(data))
	if err != nil {
		t.Fatalf("ReadDuration returned error: %v", err)
	}
	if format != "mp3" {
		t.Fatalf("format = %q, want mp3", format)
	}
	if duration < 52*time.Millisecond || duration > 53*time.Millisecond {
		t.Fatalf("duration = %s, want about 52ms", duration)
	}
}

func TestReadDurationMP4MovieHeader(t *testing.T) {
	mvhdPayload := make([]byte, 20)
	binary.BigEndian.PutUint32(mvhdPayload[12:16], 1000)
	binary.BigEndian.PutUint32(mvhdPayload[16:20], 3000)
	mvhd := testMP4Atom("mvhd", mvhdPayload)
	moov := testMP4Atom("moov", mvhd)
	ftyp := testMP4Atom("ftyp", []byte("M4A \x00\x00\x00\x00"))
	data := append(ftyp, moov...)

	duration, format, err := ReadDuration(bytes.NewReader(data))
	if err != nil {
		t.Fatalf("ReadDuration returned error: %v", err)
	}
	if format != "mp4" {
		t.Fatalf("format = %q, want mp4", format)
	}
	if duration != 3*time.Second {
		t.Fatalf("duration = %s, want 3s", duration)
	}
}

func TestReadDurationOggOpusGranule(t *testing.T) {
	firstPage := testOggPage(0, []byte("OpusHead\x01\x02\x00\x00\x80\xbb\x00\x00\x00\x00\x00"))
	lastPage := testOggPage(48000, nil)
	data := append(firstPage, lastPage...)

	duration, format, err := ReadDuration(bytes.NewReader(data))
	if err != nil {
		t.Fatalf("ReadDuration returned error: %v", err)
	}
	if format != "ogg" {
		t.Fatalf("format = %q, want ogg", format)
	}
	if duration != time.Second {
		t.Fatalf("duration = %s, want 1s", duration)
	}
}

func TestReadFLACDurationRejectsOversizedStreamInfoBlock(t *testing.T) {
	data := append([]byte("fLaC"), []byte{0x80, 0xff, 0xff, 0xff}...)

	_, err := readFLACDuration(bytes.NewReader(data))
	if !errors.Is(err, ErrDurationUnavailable) {
		t.Fatalf("readFLACDuration error = %v, want ErrDurationUnavailable", err)
	}
}

func TestReadMP4DurationAtomReadsFixedHeaderOnly(t *testing.T) {
	header := make([]byte, 32)
	binary.BigEndian.PutUint32(header[12:16], 1000)
	binary.BigEndian.PutUint32(header[16:20], 3000)

	duration, err := readMP4DurationAtom(bytes.NewReader(header), 32<<20)
	if err != nil {
		t.Fatalf("readMP4DurationAtom returned error: %v", err)
	}
	if duration != 3*time.Second {
		t.Fatalf("duration = %s, want 3s", duration)
	}
}

func testFLACStreamInfo(duration time.Duration) []byte {
	var data bytes.Buffer
	data.WriteString("fLaC")
	streamInfo := make([]byte, 34)
	sampleRate := uint64(44100)
	totalSamples := uint64(duration) * sampleRate / uint64(time.Second)
	audioBits := sampleRate<<44 | uint64(1)<<41 | uint64(15)<<36 | totalSamples
	binary.BigEndian.PutUint64(streamInfo[10:18], audioBits)
	data.Write([]byte{0x80, 0x00, 0x00, 34})
	data.Write(streamInfo)
	return data.Bytes()
}

func testMP4Atom(name string, payload []byte) []byte {
	var atom bytes.Buffer
	binary.Write(&atom, binary.BigEndian, uint32(len(payload)+8))
	atom.WriteString(name)
	atom.Write(payload)
	return atom.Bytes()
}

func testOggPage(granule uint64, packet []byte) []byte {
	header := make([]byte, 27)
	copy(header[:4], []byte("OggS"))
	binary.LittleEndian.PutUint64(header[6:14], granule)
	if len(packet) > 0 {
		header[26] = 1
	}

	var page bytes.Buffer
	page.Write(header)
	if len(packet) > 0 {
		page.WriteByte(byte(len(packet)))
		page.Write(packet)
	}
	return page.Bytes()
}
