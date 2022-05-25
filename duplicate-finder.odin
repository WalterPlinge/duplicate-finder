package duplicate_finder

import "core:fmt"
import "core:hash/xxhash"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"

files_checked: u64 = 0

main :: proc() {
	// memory tracker
	track : mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	context.allocator = mem.tracking_allocator(&track)
	defer if len(track.allocation_map) > 0 {
		fmt.println()
		for _, v in track.allocation_map {
			fmt.println(v.location, "- leaked", v.size, "bytes")
		}
	}

	// need 2 args
	if len(os.args) != 2 {
		fmt.println("Need a folder")
		return
	}

	// need a folder
	dir := os.args[1]
	if !os.exists(dir) {
		fmt.println("Invalid path:", dir)
		return
	}

	// the data layout
	Dirs :: [dynamic]string
	Hash :: map[u64]Dirs
	delete_hash :: proc(hashes: ^Hash) {
		for _, v in hashes do delete(v)
		delete(hashes^)
	}

	// this saves manually handling cloned strings
	intern: strings.Intern
	strings.intern_init(&intern)
	defer strings.intern_destroy(&intern)

	// we can first check if the files have the same size for a potential conflict
	size_hashes: Hash
	defer delete_hash(&size_hashes)

	// walk the directory
	Walk_Data :: struct { hash: ^Hash, intern: ^strings.Intern }
	wd := Walk_Data{ &size_hashes, &intern }
	context.user_ptr = &wd
	err := filepath.walk(dir, proc(info: os.File_Info, in_err: os.Errno) -> (err: os.Errno, skip_dir: bool) {
		// we don't care about errors or folders
		if in_err != 0 do return
		if info.is_dir do return

		// add dir if hash exists, add hash if does not
		data := cast(^Walk_Data) context.user_ptr
		size_hashes := data.hash
		hash := u64(info.size)
		path := strings.intern_get(data.intern, info.fullpath)
		if hash in size_hashes {
			append(&size_hashes[hash], path)
		} else {
			size_hashes[hash] = Dirs{ path }
		}
		files_checked += 1
		return
	})

	// now we can test hashes of file contents
	file_hash :: proc(file: string) -> (hash: u64, ok: bool) {
		data, success := os.read_entire_file(file)
		defer delete(data)
		if !success {
			fmt.println("Failed to read file:", file)
			return 0, false
		}
		return xxhash.XXH3_64(data), true
	}

	hashes: Hash
	defer delete_hash(&hashes)
	for _, v in size_hashes {
		if len(v) > 1 {
			for d in v {
				hash, ok := file_hash(d)
				if !ok do continue
				path := strings.intern_get(&intern, d)
				if hash in hashes {
					append(&hashes[hash], path)
				} else {
					hashes[hash] = Dirs{ path }
				}
			}
		}
	}

	// print duplicates
	conflicts := 0
	fmt.println("Potential duplicates:")
	for _, v in hashes {
		if len(v) > 1 {
			conflicts += 1
			fmt.println("\t", conflicts)
			for d in v {
				fmt.println("\t\t", d)
			}
		}
	}
	if conflicts == 0 {
		fmt.println("\tNone!")
	}
	fmt.println("Files checked:", files_checked)
}
