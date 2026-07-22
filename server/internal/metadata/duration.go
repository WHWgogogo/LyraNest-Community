package metadata

import (
	"bytes"
	"encoding/binary"
	"errors"
	"io"
	"time"
)

var ErrDurationUnavailable = errors.New("audio duration unavailable")

func ReadDuration(r io.ReadSeeker) (time.Duration, string, error) {
	header := make([]byte, 12)
	n, err := io.ReadFull(r, header)
	if err != nil && !errors.Is(err, io.ErrUnexpectedEOF) {
		return 0, "", err
	}
	if _, err := r.Seek(0, io.SeekStart); err != nil {
		return 0, "", err
	}
	header = header[:n]

	switch {
	case bytes.HasPrefix(header, []byte("fLaC")):
		duration, err := readFLACDuration(r)
		return duration, "flac", err
	case len(header) >= 12 && bytes.Equal(header[4:8], []byte("ftyp")):
		duration, err := readMP4Duration(r)
		return duration, "mp4", err
	case bytes.HasPrefix(header, []byte("OggS")):
		duration, err := readOGGDuration(r)
		return duration, "ogg", err
	case len(header) >= 12 && bytes.HasPrefix(header, []byte("RIFF")) && bytes.Equal(header[8:12], []byte("WAVE")):
		duration, err := readWAVDuration(r)
		return duration, "wav", err
	default:
		duration, err := readMP3Duration(r)
		return duration, "mp3", err
	}
}

func durationFromSamples(samples uint64, sampleRate uint32) (time.Duration, error) {
	if samples == 0 || sampleRate == 0 {
		return 0, ErrDurationUnavailable
	}
	return time.Duration(samples) * time.Second / time.Duration(sampleRate), nil
}

func readFLACDuration(r io.ReadSeeker) (time.Duration, error) {
	marker := make([]byte, 4)
	if _, err := io.ReadFull(r, marker); err != nil {
		return 0, err
	}
	if !bytes.Equal(marker, []byte("fLaC")) {
		return 0, ErrDurationUnavailable
	}

	for {
		blockHeader := make([]byte, 4)
		if _, err := io.ReadFull(r, blockHeader); err != nil {
			return 0, err
		}
		last := blockHeader[0]&0x80 != 0
		blockType := blockHeader[0] & 0x7f
		blockLen := int(blockHeader[1])<<16 | int(blockHeader[2])<<8 | int(blockHeader[3])

		if blockType == 0 {
			if blockLen != 34 {
				return 0, ErrDurationUnavailable
			}
			var data [34]byte
			if _, err := io.ReadFull(r, data[:]); err != nil {
				return 0, err
			}
			sampleRate := uint32(data[10])<<12 | uint32(data[11])<<4 | uint32(data[12])>>4
			totalSamples := (uint64(data[13]&0x0f) << 32) |
				(uint64(data[14]) << 24) |
				(uint64(data[15]) << 16) |
				(uint64(data[16]) << 8) |
				uint64(data[17])
			return durationFromSamples(totalSamples, sampleRate)
		}

		if _, err := r.Seek(int64(blockLen), io.SeekCurrent); err != nil {
			return 0, err
		}
		if last {
			break
		}
	}

	return 0, ErrDurationUnavailable
}

func readMP3Duration(r io.ReadSeeker) (time.Duration, error) {
	if err := skipID3v2(r); err != nil {
		return 0, err
	}

	var total time.Duration
	frames := 0
	for {
		position, err := r.Seek(0, io.SeekCurrent)
		if err != nil {
			return 0, err
		}

		header := make([]byte, 4)
		if _, err := io.ReadFull(r, header); err != nil {
			if errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF) {
				break
			}
			return 0, err
		}

		frame, ok := parseMP3FrameHeader(binary.BigEndian.Uint32(header))
		if !ok {
			if _, err := r.Seek(position+1, io.SeekStart); err != nil {
				return 0, err
			}
			continue
		}
		if frame.Size <= 4 {
			break
		}

		total += frame.Duration
		frames++
		if _, err := r.Seek(int64(frame.Size-4), io.SeekCurrent); err != nil {
			break
		}
	}

	if frames == 0 || total == 0 {
		return 0, ErrDurationUnavailable
	}
	return total, nil
}

func skipID3v2(r io.ReadSeeker) error {
	header := make([]byte, 10)
	n, err := io.ReadFull(r, header)
	if err != nil {
		if errors.Is(err, io.ErrUnexpectedEOF) || errors.Is(err, io.EOF) {
			_, seekErr := r.Seek(0, io.SeekStart)
			return seekErr
		}
		return err
	}
	if n < 10 || string(header[:3]) != "ID3" {
		_, err := r.Seek(0, io.SeekStart)
		return err
	}

	size := int64(header[6]&0x7f)<<21 | int64(header[7]&0x7f)<<14 | int64(header[8]&0x7f)<<7 | int64(header[9]&0x7f)
	if header[5]&0x10 != 0 {
		size += 10
	}
	_, err = r.Seek(10+size, io.SeekStart)
	return err
}

type mp3Frame struct {
	Size     int
	Duration time.Duration
}

func parseMP3FrameHeader(header uint32) (mp3Frame, bool) {
	if header&0xffe00000 != 0xffe00000 {
		return mp3Frame{}, false
	}

	versionBits := (header >> 19) & 0x3
	layerBits := (header >> 17) & 0x3
	bitrateIndex := (header >> 12) & 0xf
	sampleRateIndex := (header >> 10) & 0x3
	padding := int((header >> 9) & 0x1)
	if versionBits == 1 || layerBits == 0 || bitrateIndex == 0 || bitrateIndex == 15 || sampleRateIndex == 3 {
		return mp3Frame{}, false
	}

	sampleRate := mp3SampleRate(versionBits, sampleRateIndex)
	bitrate := mp3Bitrate(versionBits, layerBits, bitrateIndex)
	if sampleRate == 0 || bitrate == 0 {
		return mp3Frame{}, false
	}

	samples := 1152
	frameSize := 0
	switch layerBits {
	case 3:
		samples = 384
		frameSize = ((12 * bitrate * 1000 / sampleRate) + padding) * 4
	case 2:
		samples = 1152
		frameSize = 144*bitrate*1000/sampleRate + padding
	case 1:
		if versionBits == 3 {
			samples = 1152
			frameSize = 144*bitrate*1000/sampleRate + padding
		} else {
			samples = 576
			frameSize = 72*bitrate*1000/sampleRate + padding
		}
	}

	if frameSize <= 4 {
		return mp3Frame{}, false
	}
	duration := time.Duration(samples) * time.Second / time.Duration(sampleRate)
	return mp3Frame{Size: frameSize, Duration: duration}, true
}

func mp3SampleRate(versionBits uint32, index uint32) int {
	rates := map[uint32][]int{
		0: {11025, 12000, 8000},
		2: {22050, 24000, 16000},
		3: {44100, 48000, 32000},
	}
	values := rates[versionBits]
	if int(index) >= len(values) {
		return 0
	}
	return values[index]
}

func mp3Bitrate(versionBits, layerBits, index uint32) int {
	tables := map[string][]int{
		"mpeg1_layer1": {0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448},
		"mpeg1_layer2": {0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384},
		"mpeg1_layer3": {0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320},
		"mpeg2_layer1": {0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256},
		"mpeg2_layer2": {0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160},
		"mpeg2_layer3": {0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160},
	}

	prefix := "mpeg2"
	if versionBits == 3 {
		prefix = "mpeg1"
	}
	layer := map[uint32]string{3: "layer1", 2: "layer2", 1: "layer3"}[layerBits]
	values := tables[prefix+"_"+layer]
	if int(index) >= len(values) {
		return 0
	}
	return values[index]
}

func readWAVDuration(r io.ReadSeeker) (time.Duration, error) {
	header := make([]byte, 12)
	if _, err := io.ReadFull(r, header); err != nil {
		return 0, err
	}
	if !bytes.HasPrefix(header, []byte("RIFF")) || !bytes.Equal(header[8:12], []byte("WAVE")) {
		return 0, ErrDurationUnavailable
	}

	var byteRate uint32
	var dataSize uint32
	for {
		chunkHeader := make([]byte, 8)
		if _, err := io.ReadFull(r, chunkHeader); err != nil {
			if errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF) {
				break
			}
			return 0, err
		}
		chunkID := string(chunkHeader[:4])
		chunkSize := binary.LittleEndian.Uint32(chunkHeader[4:8])

		switch chunkID {
		case "fmt ":
			if chunkSize < 12 {
				if _, err := r.Seek(int64(chunkSize), io.SeekCurrent); err != nil {
					return 0, err
				}
				break
			}
			var data [12]byte
			if _, err := io.ReadFull(r, data[:]); err != nil {
				return 0, err
			}
			byteRate = binary.LittleEndian.Uint32(data[8:12])
			if _, err := r.Seek(int64(chunkSize)-int64(len(data)), io.SeekCurrent); err != nil {
				return 0, err
			}
		case "data":
			dataSize = chunkSize
			if _, err := r.Seek(int64(chunkSize), io.SeekCurrent); err != nil {
				return 0, err
			}
		default:
			if _, err := r.Seek(int64(chunkSize), io.SeekCurrent); err != nil {
				return 0, err
			}
		}

		if chunkSize%2 == 1 {
			if _, err := r.Seek(1, io.SeekCurrent); err != nil {
				return 0, err
			}
		}
		if byteRate > 0 && dataSize > 0 {
			return time.Duration(dataSize) * time.Second / time.Duration(byteRate), nil
		}
	}

	return 0, ErrDurationUnavailable
}

func readMP4Duration(r io.ReadSeeker) (time.Duration, error) {
	end, err := r.Seek(0, io.SeekEnd)
	if err != nil {
		return 0, err
	}
	if _, err := r.Seek(0, io.SeekStart); err != nil {
		return 0, err
	}
	return findMP4Duration(r, end, 0)
}

func findMP4Duration(r io.ReadSeeker, end int64, depth int) (time.Duration, error) {
	if depth > 8 {
		return 0, ErrDurationUnavailable
	}

	for {
		position, err := r.Seek(0, io.SeekCurrent)
		if err != nil {
			return 0, err
		}
		if position+8 > end {
			break
		}

		size, name, headerSize, err := readMP4AtomHeader(r, end-position)
		if err != nil {
			return 0, err
		}
		if size < headerSize || position+int64(size) > end {
			return 0, ErrDurationUnavailable
		}
		payloadEnd := position + int64(size)

		switch name {
		case "mvhd", "mdhd":
			duration, err := readMP4DurationAtom(r, int64(size-headerSize))
			if err == nil && duration > 0 {
				return duration, nil
			}
		case "moov", "trak", "mdia":
			duration, err := findMP4Duration(r, payloadEnd, depth+1)
			if err == nil && duration > 0 {
				return duration, nil
			}
		}

		if _, err := r.Seek(payloadEnd, io.SeekStart); err != nil {
			return 0, err
		}
	}

	return 0, ErrDurationUnavailable
}

func readMP4AtomHeader(r io.Reader, remaining int64) (uint64, string, uint64, error) {
	header := make([]byte, 8)
	if _, err := io.ReadFull(r, header); err != nil {
		return 0, "", 0, err
	}
	size := uint64(binary.BigEndian.Uint32(header[:4]))
	name := string(header[4:8])
	headerSize := uint64(8)
	if size == 1 {
		largeSize := make([]byte, 8)
		if _, err := io.ReadFull(r, largeSize); err != nil {
			return 0, "", 0, err
		}
		size = binary.BigEndian.Uint64(largeSize)
		headerSize = 16
	}
	if size == 0 {
		size = uint64(remaining)
	}
	return size, name, headerSize, nil
}

func readMP4DurationAtom(r io.Reader, payloadSize int64) (time.Duration, error) {
	if payloadSize < 20 {
		return 0, ErrDurationUnavailable
	}

	var header [32]byte
	headerLength := payloadSize
	if headerLength > int64(len(header)) {
		headerLength = int64(len(header))
	}
	if _, err := io.ReadFull(r, header[:headerLength]); err != nil {
		return 0, err
	}

	version := header[0]
	if version == 1 {
		if headerLength < 32 {
			return 0, ErrDurationUnavailable
		}
		timescale := binary.BigEndian.Uint32(header[20:24])
		duration := binary.BigEndian.Uint64(header[24:32])
		return durationFromSamples(duration, timescale)
	}

	if headerLength < 20 {
		return 0, ErrDurationUnavailable
	}
	timescale := binary.BigEndian.Uint32(header[12:16])
	duration := uint64(binary.BigEndian.Uint32(header[16:20]))
	return durationFromSamples(duration, timescale)
}

func readOGGDuration(r io.ReadSeeker) (time.Duration, error) {
	var packet bytes.Buffer
	var sampleRate uint32
	var lastGranule uint64
	hasGranule := false

	for {
		header := make([]byte, 27)
		if _, err := io.ReadFull(r, header); err != nil {
			if errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF) {
				break
			}
			return 0, err
		}
		if !bytes.Equal(header[:4], []byte("OggS")) {
			return 0, ErrDurationUnavailable
		}

		granule := binary.LittleEndian.Uint64(header[6:14])
		if granule != ^uint64(0) {
			lastGranule = granule
			hasGranule = true
		}

		segments := int(header[26])
		segmentTable := make([]byte, segments)
		if _, err := io.ReadFull(r, segmentTable); err != nil {
			return 0, err
		}
		payloadSize := 0
		for _, segment := range segmentTable {
			payloadSize += int(segment)
		}
		payload := make([]byte, payloadSize)
		if _, err := io.ReadFull(r, payload); err != nil {
			return 0, err
		}

		offset := 0
		for _, segment := range segmentTable {
			next := offset + int(segment)
			if sampleRate == 0 {
				if packet.Len()+int(segment) > 64<<10 {
					return 0, ErrDurationUnavailable
				}
				packet.Write(payload[offset:next])
			}
			offset = next
			if segment < 255 {
				if sampleRate == 0 {
					sampleRate = oggPacketSampleRate(packet.Bytes())
				}
				packet.Reset()
			}
		}
	}

	if !hasGranule || sampleRate == 0 {
		return 0, ErrDurationUnavailable
	}
	return durationFromSamples(lastGranule, sampleRate)
}

func oggPacketSampleRate(packet []byte) uint32 {
	switch {
	case len(packet) >= 16 && bytes.HasPrefix(packet, []byte("\x01vorbis")):
		return binary.LittleEndian.Uint32(packet[12:16])
	case bytes.HasPrefix(packet, []byte("OpusHead")):
		return 48000
	default:
		return 0
	}
}
