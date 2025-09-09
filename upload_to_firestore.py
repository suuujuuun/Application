import pandas as pd
from google.cloud import firestore

# Firestore 데이터베이스 클라이언트 초기화
# Firebase Console에서 확인한 정확한 프로젝트 ID를 입력하세요. 
# 보통 'study-tool-fr1'과 같은 형식입니다.
db = firestore.Client(project='study-tool-fr1')

# 읽어올 CSV 파일 경로
csv_file_path = '/Users/seungjun/Desktop/medical_terms_for_english_study.csv'

# Firestore 컬렉션 이름
collection_name = 'Med_voca'

print(f"Reading CSV file from: {csv_file_path}")
try:
    df = pd.read_csv(csv_file_path)
except FileNotFoundError:
    print(f"Error: The file was not found at {csv_file_path}")
    exit()


print(f"Starting upload to '{collection_name}' collection in project 'study tool fr1'...")

# CSV의 각 행을 Firestore 문서로 업로드/업데이트
for index, row in df.iterrows():
    # CSV의 컬럼 이름('English word', 'English explanation')을 정확히 사용합니다.
    english_word = row.get('English word')
    english_explanation = row.get('English explanation')

    # 'English word'가 비어있지 않은지 확인
    if english_word and pd.notna(english_word):
        # Replace forward slashes with hyphens for the document ID
        document_id = english_word.replace('/', '-')
        
        # Firestore에 저장할 데이터 (필드명을 'word', 'definition'으로 변경)
        data_to_upload = {
            'word': english_word,
            'definition': english_explanation if pd.notna(english_explanation) else ""
        }

        # 'English word' 값을 문서 ID로 사용
        doc_ref = db.collection(collection_name).document(document_id)
        
        # 문서를 생성하거나 덮어씁니다.
        doc_ref.set(data_to_upload)
        print(f"Processed document for: {english_word}")
    else:
        print(f"Skipping row {index+2} due to missing 'English word'.")

print("Upload/update complete.")
