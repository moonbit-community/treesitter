// Port of tree-sitter crates/cli/src/fuzz/edits.rs.

///|
pub(all) struct Edit {
  position : Int32
  deleted_length : Int32
  inserted_text : Array[Byte]
} derive(Debug)

///|
pub fn invert_edit(input : ArrayView[Byte], edit : Edit) -> Edit {
  let position = edit.position
  let removed_content = input[position:position + edit.deleted_length]
  {
    position,
    deleted_length: edit.inserted_text.length(),
    inserted_text: removed_content.to_owned(),
  }
}

///|
pub fn get_random_edit(rand : Rand, input : ArrayView[Byte]) -> Edit {
  let choice = rand.unsigned(10)
  if choice < 2 {
    // Insert text at end
    let inserted_text = rand.words(3)
    { position: input.length(), deleted_length: 0, inserted_text, }
  } else if choice < 5 {
    // Delete text from the end
    let deleted_length = rand.unsigned(30)
    let deleted_length = if deleted_length < input.length() {
      deleted_length
    } else {
      input.length()
    }
    {
      position: input.length() - deleted_length,
      deleted_length,
      inserted_text: [],
    }
  } else if choice < 8 {
    // Insert at a random position
    let position = rand.unsigned(input.length())
    let word_count = 1 + rand.unsigned(3)
    let inserted_text = rand.words(word_count)
    { position, deleted_length: 0, inserted_text, }
  } else {
    // Replace at random position
    let position = rand.unsigned(input.length())
    let deleted_length = rand.unsigned(input.length() - position)
    let word_count = 1 + rand.unsigned(3)
    let inserted_text = rand.words(word_count)
    { position, deleted_length, inserted_text, }
  }
}
