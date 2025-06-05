import streamlit as st
import boto3
import os
import json
import pandas as pd
import time
from datetime import datetime

st.set_page_config(page_title="EKS Operational Review Agent", layout="wide")

st.title("EKS Operational Review Agent")
st.write("This tool helps you perform operational reviews of your EKS clusters using Amazon Bedrock.")

# Initialize session state
if 'initialized' not in st.session_state:
    st.session_state.initialized = False
if 'report_generated' not in st.session_state:
    st.session_state.report_generated = False
if 'report_data' not in st.session_state:
    st.session_state.report_data = None

# Input form
with st.form("credentials_form"):
    st.subheader("AWS Credentials and Configuration")
    
    col1, col2 = st.columns(2)
    with col1:
        aws_access_key = st.text_input("AWS Access Key ID", type="password")
    with col2:
        aws_secret_key = st.text_input("AWS Secret Access Key", type="password")
    
    col1, col2 = st.columns(2)
    with col1:
        eks_cluster_name = st.text_input("EKS Cluster Name", value="eks-cluster-1")
    with col2:
        knowledge_base_id = st.text_input("Knowledge Base ID")
    
    submit_button = st.form_submit_button("Initialize")
    
    if submit_button:
        try:
            # Set AWS credentials
            os.environ['AWS_ACCESS_KEY_ID'] = aws_access_key
            os.environ['AWS_SECRET_ACCESS_KEY'] = aws_secret_key
            
            # Initialize AWS clients
            eks_client = boto3.client('eks')
            bedrock_client = boto3.client('bedrock-runtime', region_name='us-east-1')
            bedrock_agent_client = boto3.client('bedrock-agent', region_name='us-east-1')
            
            # Test connections
            eks_client.describe_cluster(name=eks_cluster_name)
            
            # Check if knowledge base exists
            if knowledge_base_id:
                bedrock_agent_client.get_knowledge_base(knowledgeBaseId=knowledge_base_id)
            
            st.session_state.initialized = True
            st.session_state.eks_client = eks_client
            st.session_state.bedrock_client = bedrock_client
            st.session_state.bedrock_agent_client = bedrock_agent_client
            st.session_state.eks_cluster_name = eks_cluster_name
            st.session_state.knowledge_base_id = knowledge_base_id
            
            st.success("Successfully initialized connections!")
        except Exception as e:
            st.error(f"Error initializing connections: {str(e)}")

# Only show the rest if initialized
if st.session_state.initialized:
    st.subheader("EKS Cluster Information")
    
    try:
        # Get cluster info
        cluster_info = st.session_state.eks_client.describe_cluster(name=st.session_state.eks_cluster_name)
        
        # Display basic cluster info
        col1, col2, col3 = st.columns(3)
        with col1:
            st.metric("Kubernetes Version", cluster_info['cluster']['version'])
        with col2:
            st.metric("Status", cluster_info['cluster']['status'])
        with col3:
            st.metric("Endpoint Access", "Public" if cluster_info['cluster']['resourcesVpcConfig']['endpointPublicAccess'] else "Private")
        
        # Generate report button
        if st.button("Generate Report"):
            with st.spinner("Generating report... This may take a few minutes."):
                # Simulate report generation
                time.sleep(5)
                
                # Create a sample report
                report_data = {
                    "cluster_name": st.session_state.eks_cluster_name,
                    "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                    "findings": [
                        {
                            "category": "Security",
                            "severity": "High",
                            "title": "Public endpoint access enabled",
                            "description": "The EKS cluster has public endpoint access enabled, which increases the attack surface.",
                            "recommendation": "Consider disabling public endpoint access and use private endpoints with VPC endpoints instead."
                        },
                        {
                            "category": "Security",
                            "severity": "Medium",
                            "title": "Missing network policies",
                            "description": "The EKS cluster does not have network policies implemented to restrict pod-to-pod communication.",
                            "recommendation": "Implement network policies to control traffic between pods."
                        },
                        {
                            "category": "Operations",
                            "severity": "Medium",
                            "title": "Outdated Kubernetes version",
                            "description": f"The EKS cluster is running Kubernetes version {cluster_info['cluster']['version']}, which may not be the latest available version.",
                            "recommendation": "Consider upgrading to the latest EKS version for security patches and new features."
                        }
                    ]
                }
                
                st.session_state.report_generated = True
                st.session_state.report_data = report_data
                st.success("Report generated successfully!")
    
    except Exception as e:
        st.error(f"Error retrieving cluster information: {str(e)}")

# Display report if generated
if st.session_state.report_generated and st.session_state.report_data:
    st.subheader("Security Assessment Report")
    
    report = st.session_state.report_data
    
    st.write(f"**Cluster Name:** {report['cluster_name']}")
    st.write(f"**Generated At:** {report['timestamp']}")
    
    # Display findings
    st.subheader("Findings")
    
    # Convert findings to DataFrame for better display
    findings_df = pd.DataFrame(report['findings'])
    
    # Display findings by severity
    severities = ["High", "Medium", "Low"]
    for severity in severities:
        severity_findings = findings_df[findings_df['severity'] == severity]
        if not severity_findings.empty:
            st.write(f"### {severity} Severity Findings")
            for _, finding in severity_findings.iterrows():
                with st.expander(f"{finding['title']} ({finding['category']})"):
                    st.write(f"**Description:** {finding['description']}")
                    st.write(f"**Recommendation:** {finding['recommendation']}")
    
    # Download options
    col1, col2 = st.columns(2)
    with col1:
        if st.button("Download as PDF"):
            st.info("PDF download functionality would be implemented here.")
    with col2:
        if st.button("Download as CSV"):
            st.info("CSV download functionality would be implemented here.")
