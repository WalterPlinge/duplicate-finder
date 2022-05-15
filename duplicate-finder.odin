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
		for _, v in hashes do for s in v do delete(s)
		for _, v in hashes do delete(v)
		delete(hashes^)
	}

	// we can first check if the files have the same size for a potential conflict
	size_hashes: Hash
	defer delete_hash(&size_hashes)

	// walk the directory
	context.user_ptr = &size_hashes
	err := filepath.walk(dir, proc(info: os.File_Info, in_err: os.Errno) -> (err: os.Errno, skip_dir: bool) {
		// we don't care about errors or folders
		if in_err != 0 do return
		if info.is_dir do return

		// add dir if hash exists, add hash if does not
		size_hashes := cast(^Hash) context.user_ptr
		hash := u64(info.size)
		if hash in size_hashes {
			append(&size_hashes[hash], strings.clone(info.fullpath))
		} else {
			size_hashes[hash] = Dirs{ strings.clone(info.fullpath) }
		}
		files_checked += 1
		return
	})

	// now we can test hashes of file contents
	hashes: Hash
	defer delete_hash(&hashes)
	for _, v in size_hashes {
		if len(v) > 1 {
			for d in v {
				data, success := os.read_entire_file(d)
				if !success {
					fmt.println("Failed to read file:", d)
					continue
				}
				defer delete(data)

				hash := xxhash.XXH3_64(data)
				if hash in hashes {
					append(&hashes[hash], strings.clone(d))
				} else {
					hashes[hash] = Dirs{ strings.clone(d) }
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
