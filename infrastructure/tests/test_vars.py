import subprocess
import json

def test_tf_outputs():
    # This script pulls the live data from your Terraform state
    try:
        output = subprocess.check_output(['terraform', 'output', '-json'])
        data = json.loads(output)
        
        nats = data['nats_transporter_url']['value']
        mongo = data['mongodb_connection_uri']['value']
        
        print(f"✅ Success! Your app will connect to NATS at: {nats}")
        print(f"✅ Success! Your app will connect to MongoDB at: {mongo}")
        
    except Exception as e:
        print("❌ Error: Could not read Terraform outputs. Did you run 'terraform apply'?")

if __name__ == "__main__":
    test_tf_outputs()